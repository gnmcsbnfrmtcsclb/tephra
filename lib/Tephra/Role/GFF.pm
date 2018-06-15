package Tephra::Role::GFF;

use 5.014;
use Moose::Role;
use Sort::Naturally;
use Bio::GFF3::LowLevel qw(gff3_parse_feature);
use Path::Class::File;
#use Data::Dump::Color;
use namespace::autoclean;

=head1 NAME

Tephra::Role::GFF - Utility methods for working with GFF files

=head1 VERSION

Version 0.11.0

=cut

our $VERSION = '0.11.0';
$VERSION = eval $VERSION;

#
# methods
#
sub collect_gff_features {
    my $self = shift;
    my ($gff) = @_;

    my $header;
    open my $in, '<', $gff or die "\n[ERROR]: Could not open file: $gff\n";
    while (<$in>) {
	chomp;
	next if /^###$/;
	if (/^##?\w+/) {
	    $header .= $_."\n";
	}
	else {
	    last;
	}
    }
    close $in;
    chomp $header;

    open my $gffio, '<', $gff or die "\n[ERROR]: Could not open file: $gff\n";

    my ($start, $end, $region, $key, %features);
    while (my $line = <$gffio>) {
        chomp $line;
        next if $line =~ /^#/;
        my $feature = gff3_parse_feature( $line );
        if ($feature->{type} eq 'repeat_region') {
            $region = @{$feature->{attributes}{ID}}[0];
            ($start, $end) = @{$feature}{qw(start end)};
	    $key = join "||", $region, $start, $end;

        }
	if ($feature->{type} ne 'repeat_region') {
            if ($feature->{start} >= $start && $feature->{end} <= $end) {
		push @{$features{$key}}, $feature;
            }
        }
    }
    close $gffio;

    return ($header, \%features);
}

sub get_parent_coords {
    my $self = shift;
    my ($parent, $coord_map) = @_;

    my ($seq_id, $start, $end) = split /\|\|/, $coord_map->{$parent};
    my $pkey = join "||", $parent, $start, $end;

    return ($seq_id, $pkey);
}

sub extract_ltr_sequences {
    my $self = shift;
    my $fasta = $self->genome->absolute->resolve;
    my $gff   = $self->gff->absolute->resolve;
    
    my ($name, $path, $suffix) = fileparse($gff, qr/\.[^.]*/);
    my $dir = File::Spec->catdir($path, $name.'_ltrages');
    unless ( -d $dir ) {
        make_path( $dir, {verbose => 0, mode => 0771,} );
    }

    my ($header, $features) = $self->collect_gff_features($gff);
    my $index = $self->index_ref($fasta);

    my ($family, %ltrs, %seen, %coord_map);
    for my $rep_region (keys %$features) {
        for my $ltr_feature (@{$features->{$rep_region}}) {
            if ($ltr_feature->{type} =~ /(?:LTR|TRIM|LARD)_retrotransposon/) {
                my $elem_id = @{$ltr_feature->{attributes}{ID}}[0];
                $family  = @{$ltr_feature->{attributes}{family}}[0];
                my ($start, $end) = @{$ltr_feature}{qw(start end)};
                my $key = join "||", $family, $elem_id, $start, $end;
                $ltrs{$key}{'full'} = join "||", @{$ltr_feature}{qw(seq_id type start end)};
                $coord_map{$elem_id} = join "||", @{$ltr_feature}{qw(seq_id start end)};
            }
            if ($ltr_feature->{type} eq 'long_terminal_repeat') {
                my $parent = @{$ltr_feature->{attributes}{Parent}}[0];
                my ($seq_id, $pkey) = $self->get_parent_coords($parent, \%coord_map);
                if ($seq_id eq $ltr_feature->{seq_id}) {
                    my ($type, $start, $end, $strand) = 
                        @{$ltr_feature}{qw(type start end strand)};
                    $strand //= '?';
                    my $ltrkey = join "||", $seq_id, $type, $start, $end, $strand;
                    my $parent_key = join "||", $family, $pkey;
                    push @{$ltrs{$parent_key}{'ltrs'}}, $ltrkey unless exists $seen{$ltrkey};
                    $seen{$ltrkey} = 1;
                }
            }
        }
    }

    my @files;
    my $ltrct = 0;
    my $orientation;
    for my $ltr (nsort keys %ltrs) {
        my ($family, $element, $rstart, $rend) = split /\|\|/, $ltr;
        my ($seq_id, $type, $start, $end) = split /\|\|/, $ltrs{$ltr}{'full'};
        my $ltr_file = join "_", $family, $element, $seq_id, $start, $end, 'ltrs.fasta';
        my $ltrs_out = File::Spec->catfile($dir, $ltr_file);
        die "\n[ERROR]: $ltrs_out exists. This will cause problems downstream. Please remove the previous ".
            "results and try again. Exiting.\n" if -e $ltrs_out;
        push @files, $ltrs_out;
        open my $ltrs_outfh, '>>', $ltrs_out or die "\n[ERROR]: Could not open file: $ltrs_out\n";

        for my $ltr_repeat (@{$ltrs{$ltr}{'ltrs'}}) {
            #ltr: Contig57_HLAC-254L24||long_terminal_repeat||60101||61950||+
            my ($src, $ltrtag, $s, $e, $strand) = split /\|\|/, $ltr_repeat;
            my $ltrid;

            if ($ltrct) {
                $orientation = '5prime' if $strand eq '-';
                $orientation = '3prime'  if $strand eq '+';
                $orientation = 'unk-prime-r' if $strand eq '?';
                $ltrid = join "_", $orientation, $family, $element, $src, $s, $e;
                $self->write_element_parts($index, $src, $s, $e, $ltrs_outfh, $ltrid);
                $ltrct = 0;
            }
            else {
                $orientation = '5prime' if $strand eq '+';
                $orientation = '3prime' if $strand eq '-';
                $orientation = 'unk-prime-f' if $strand eq '?';
                $ltrid = join "_", $orientation, $family, $element, $src, $s, $e;
                $self->write_element_parts($index, $src, $s, $e, $ltrs_outfh, $ltrid);
                $ltrct++;
            }
        }
    }

    return (\@files, $dir);
}

sub extract_tir_sequences {
    my $self = shift;
    my $fasta = $self->genome->absolute->resolve;
    my $gff   = $self->gff->absolute->resolve;
    
    my ($name, $path, $suffix) = fileparse($gff, qr/\.[^.]*/);
    my $dir = File::Spec->catdir($path, $name.'_tirages');
    unless ( -d $dir ) {
        make_path( $dir, {verbose => 0, mode => 0771,} );
    }

    my ($header, $features) = $self->collect_gff_features($gff);
    my $index = $self->index_ref($fasta);

    #dd $features;
    my ($family, %tirs, %seen, %coord_map);
    for my $rep_region (keys %$features) {
        for my $tir_feature (@{$features->{$rep_region}}) {
            if ($tir_feature->{type} =~ /terminal_inverted_repeat_element|MITE/i) {
                my $elem_id = @{$tir_feature->{attributes}{ID}}[0];
                next unless defined $elem_id;
                $family = @{$tir_feature->{attributes}{family}}[0];
                my ($start, $end) = @{$tir_feature}{qw(start end)};
                my $key = defined $family ? join "||", $family, $elem_id, $start, $end 
                    : join "||", $elem_id, $start, $end;
                $tirs{$key}{'full'} = join "||", @{$tir_feature}{qw(seq_id type start end)};
                $coord_map{$elem_id} = join "||", @{$tir_feature}{qw(seq_id start end)};
            }
            if ($tir_feature->{type} eq 'terminal_inverted_repeat') {
                my $parent = @{$tir_feature->{attributes}{Parent}}[0];
                my ($seq_id, $pkey) = $self->get_parent_coords($parent, \%coord_map);
                if ($seq_id eq $tir_feature->{seq_id}) {
                    my ($type, $start, $end, $strand) = 
                        @{$tir_feature}{qw(type start end strand)};
                    $strand //= '?';
                    my $tirkey = join "||", $seq_id, $type, $start, $end, $strand;
                    $pkey = defined $family ? join "||", $family, $pkey : $pkey;
                    push @{$tirs{$pkey}{'tirs'}}, $tirkey unless exists $seen{$tirkey};
                    $seen{$tirkey} = 1;
                }
            }
        }
    }

    my @files;
    my $tirct = 0;
    my $orientation;
    for my $tir (sort keys %tirs) {
        my ($family, $element, $rstart, $rend) = split /\|\|/, $tir;
        my ($seq_id, $type, $start, $end) = split /\|\|/, $tirs{$tir}{'full'};
        my $tir_file = join "_", $family, $element, $seq_id, $start, $end, 'tirs.fasta';
        my $tirs_out = File::Spec->catfile($dir, $tir_file);
        die "\n[ERROR]: $tirs_out exists. This will cause problems downstream. Please remove the previous ".
            "results and try again. Exiting.\n" if -e $tirs_out;
        push @files, $tirs_out;
        open my $tirs_outfh, '>>', $tirs_out or die "\n[ERROR]: Could not open file: $tirs_out\n";

        for my $tir_repeat (@{$tirs{$tir}{'tirs'}}) {
            #Contig57_HLAC-254L24||terminal_inverted_repeat||60101||61950||+
            my ($src, $tirtag, $s, $e, $strand) = split /\|\|/, $tir_repeat;
            my $tirid;

            if ($tirct) {
                $orientation = '5prime' if $strand eq '-';
                $orientation = '3prime'  if $strand eq '+';
                $orientation = 'unk-prime-r' if $strand eq '?';
                $self->write_tir_parts($index, $src, $element, $s, $e, $tirs_outfh, $orientation, $family);
                $tirct = 0;
            }
            else {
                $orientation = '5prime' if $strand eq '+';
                $orientation = '3prime' if $strand eq '-';
                $orientation = 'unk-prime-f' if $strand eq '?';
                $self->write_tir_parts($index, $src, $element, $s, $e, $tirs_outfh, $orientation, $family);
                $tirct++;
            }
        }
    }

    return (\@files, $dir);
}


=head1 AUTHOR

S. Evan Staton, C<< <evan at evanstaton.com> >>

=head1 BUGS

Please report any bugs or feature requests through the project site at 
L<https://github.com/sestaton/tephra/issues>. I will be notified,
and there will be a record of the issue. Alternatively, I can also be 
reached at the email address listed above to resolve any questions.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Tephra::Role::GFF


=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015- S. Evan Staton

This program is distributed under the MIT (X11) License, which should be distributed with the package. 
If not, it can be found here: L<http://www.opensource.org/licenses/mit-license.php>

=cut

1;
