package Tephra::TIR::TIRSearch;

use 5.014;
use Moose;
use Bio::GFF3::LowLevel qw(gff3_format_feature);
use List::MoreUtils     qw(uniq);
use List::UtilsBy       qw(nsort_by);
use Cwd                 qw(abs_path);
use File::Copy          qw(move);
use File::Path          qw(remove_tree);
use File::Spec;
use File::Basename;
use Sort::Naturally;
use Path::Class::File;
use Try::Tiny;
use Tephra::Config::Exe;
use Tephra::Annotation::FilterTandems;
use Carp 'croak';
#use Data::Dump::Color;
use namespace::autoclean;

with 'Tephra::Role::Logger',
     'Tephra::Role::GFF',
     'Tephra::Role::Util',
     'Tephra::Role::Run::GT';

has outfile => (
      is        => 'ro',
      isa       => 'Maybe[Str]',
      predicate => 'has_outfile',
      required  => 0,
);

has genefile => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    required => 1,
    coerce   => 1,
);

has logfile => (
      is        => 'ro',
      isa       => 'Str',
      predicate => 'has_logfile',
);

has threads => (
    is        => 'ro',
    isa       => 'Int',
    predicate => 'has_threads',
    lazy      => 1,
    default   => 1,
);

=head1 NAME

Tephra::TIR::TIRSearch - Find TIR transposons in a reference genome

=head1 VERSION

Version 0.12.5

=cut

our $VERSION = '0.12.5';
$VERSION = eval $VERSION;

sub tir_search {
    my $self = shift;
    my ($index) = @_;
    
    my $genome   = $self->genome->absolute->resolve;
    my $genefile = $self->genefile->absolute->resolve;
    my $hmmdb    = $self->hmmdb;
    my $outfile  = $self->outfile;
    my $logfile  = $self->logfile;
    my $threads  = $self->threads;
    my (%suf_args, %tirv_cmd);

    my ($name, $path, $suffix) = fileparse($genome, qr/\.[^.]*/);
    if ($name =~ /(\.fa.*)/) {
	$name =~ s/$1//;
    }
    
    my $gff = $outfile // File::Spec->catfile( abs_path($path), $name.'_tirs.gff3' );
    my $fas = $gff;
    $fas =~ s/\.gff.*/.fasta/;

    my @tirv_opts = qw(-seqids -mintirlen -mintirdist -index -hmms);

    my @tirv_args = ("yes","27","100",$index,$hmmdb);
    @tirv_cmd{@tirv_opts} = @tirv_args;
    
    my $log = $self->get_tephra_logger($logfile);
    my $tirv_succ = $self->run_tirvish(\%tirv_cmd, $gff, $log);
    #remove_tree($model_dir, { safe => 1 });
    $self->clean_indexes($path) if $self->clean;

    my $ftandem_obj = Tephra::Annotation::FilterTandems->new(
            genome   => $genome,
            genefile => $genefile,
            gff      => $gff,
            threads  => $threads,
            type     => 'TIR',
            blast_hit_cov => 50,
            blast_hit_pid => 70,
            blast_hit_len => 10,
    );

    my ($filtered_gff, $filtered_stats) = $ftandem_obj->filter_tandem_genes;
    my ($rt_filtered_gff, $rt_filtered_fas) = $self->_filter_tir_gff($filtered_gff, $fas);
    
    return $filtered_gff;
}

sub _filter_tir_gff {
    my $self = shift;
    my ($gff, $fas) = @_;
    my $genome = $self->genome->absolute->resolve;

    my ($name, $path, $suffix) = fileparse($gff, qr/\.[^.]*/);
    my $outfile = File::Spec->catfile( abs_path($path), $name.'_filtered.gff3' );
    open my $out, '>', $outfile or die "\n[ERROR]: Could not open file: $outfile\n";
    open my $faout, '>>', $fas or die "\n[ERROR]: Could not open file: $fas\n";
    
    my %tirs;
    my ($header, $features) = $self->collect_gff_features($gff);
    say $out $header;

    my $index = $self->index_ref($genome);

    my @rt = qw(rve rvt rvp gag chromo);
    
    my @rt_domains;
    for my $seq_id (keys %$features) {
	for my $rep_region (keys %{$features->{$seq_id}}) {
	    for my $tir_feature (@{$features->{$seq_id}{$rep_region}}) {
		if ($tir_feature->{type} eq 'protein_match') {
		    my $pdom_name = $tir_feature->{attributes}{name}[0];
		    #say STDERR "pdom: $pdom_name";
		    if ($pdom_name =~ /rve|rvt|rvp|gag|chromo|rnase|athila|zf-cchc|ubn2/i) {
			# should perhaps make filtering an option
			#delete $features->{$seq_id}{$rep_region};
			push @rt_domains, join "~~", $seq_id, $rep_region;
		    }
		}
	    }
	}
    }
    
    @rt_domains = uniq(@rt_domains);
     for my $rep_region (@rt_domains) {
	my ($chr, $rregion) = split /\~\~/, $rep_region;
	delete $features->{$chr}{$rregion};
    }
 
    my ($seq_id, $source, $tir_start, $tir_end, $tir_feats, $strand, $fas_id);
    my $skip_region = 0;
    for my $chr_id (nsort keys %$features) {
	for my $rep_region (nsort_by { m/repeat_region\d+\.?\d+?\|\|(\d+)\|\|\d+/ and $1 } keys %{$features->{$chr_id}}) {
	    my ($rreg_id, $start, $end) = split /\|\|/, $rep_region;
	    my $len = $end - $start + 1;
	    
	    for my $tir_feature (@{$features->{$chr_id}{$rep_region}}) {
		if ($tir_feature->{type} eq 'terminal_inverted_repeat_element') {
		    my $elem_id = $tir_feature->{attributes}{ID}[0];
		    ($seq_id, $source, $tir_start, $tir_end, $strand) 
			= @{$tir_feature}{qw(seq_id source start end strand)};
		    $fas_id = join "_", $elem_id, $seq_id, $tir_start, $tir_end;
		}
		## NB: This is to bypass a bug in TIRvish which outputs a TIR element with two TIRs 
		## of identical length to the full element (10/29/2018 SES)
		if ($tir_feature->{type} eq 'terminal_inverted_repeat') {
		    my ($rep_seq_id, $rep_source, $rep_tir_start, $rep_tir_end, $rep_strand)
			= @{$tir_feature}{qw(seq_id source start end strand)};
		    if ($tir_start == $rep_tir_start && $tir_end == $rep_tir_end) {
			$skip_region++;
		    }
		}
		
		my $gff3_str = gff3_format_feature($tir_feature);
		$tir_feats .= $gff3_str;
	    }

	    unless ($skip_region == 2) {
		chomp $tir_feats;
		say $out join "\t", $seq_id, $source, 'repeat_region', $start, $end, '.', $strand, '.', "ID=$rreg_id";
		say $out $tir_feats;
		
		$self->write_element_parts($index, $seq_id, $tir_start, $tir_end, $faout, $fas_id);
	    }

	    undef $tir_feats;
	    $skip_region = 0;
	}
    }
    close $out;

    move $outfile, $gff or die "\n[ERROR]: move failed: $!\n";

    return ($gff, $fas);
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

    perldoc Tephra::TIR::TIRSearch


=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015- S. Evan Staton

This program is distributed under the MIT (X11) License, which should be distributed with the package. 
If not, it can be found here: L<http://www.opensource.org/licenses/mit-license.php>

=cut

__PACKAGE__->meta->make_immutable;

1;
