package Tephra::Genome::MaskRef;

use 5.010;
use Moose;
use Cwd;
use File::Spec;
use File::Find;
use File::Basename;
use File::Path  qw(make_path remove_tree);
use List::Util  qw(sum);
use Log::Any    qw($log);
use Time::HiRes qw(gettimeofday);
use Sort::Naturally;
use Set::IntervalTree;
use Parallel::ForkManager;
use namespace::autoclean;
#use Data::Dump::Color qw(dump dd);

with 'Tephra::Role::Util';

=head1 NAME

Tephra::Genome::MaskRef - Mask a reference with repeats to reduce false positives

=head1 VERSION

Version 0.04.0

=cut

our $VERSION = '0.04.0';
$VERSION = eval $VERSION;

has genome => (
      is       => 'ro',
      isa      => 'Maybe[Str]',
      required => 1,
      coerce   => 0,
);

has repeatdb => (
      is       => 'ro',
      isa      => 'Maybe[Str]',
      required => 0,
      coerce   => 0,
);

has outfile => (
    is       => 'ro',
    isa      => 'Maybe[Str]',
    required => 1,
    coerce   => 0,
);

has clean => (
    is       => 'ro',
    isa      => 'Bool',
    required => 0,
    default  => 1,
);

has threads => (
    is        => 'ro',
    isa       => 'Int',
    predicate => 'has_threads',
    lazy      => 1,
    default   => 1,
);

has splitsize => (
    is        => 'ro',
    isa       => 'Num',
    predicate => 'has_splitsize',
    lazy      => 1,
    default   => 5e4,
);

has hitlength => (
    is      => 'ro',
    isa     => 'Int',
    default => 70,
);

sub mask_reference {
    my $self = shift;
    my $genome  = $self->genome;
    my $threads = $self->threads;

    my $t0 = gettimeofday();
    my ($name, $path, $suffix) = fileparse($genome, qr/\.[^.]*/);
    if ($name =~ /(\.fa.*)/) {
	$name =~ s/$1//;
    }

    my $outfile  = $self->outfile // File::Spec->catfile($path, $name.'_masked.fas');
    if (-e $outfile) {
	say "\nERROR: '$outfile' already exists. Please delete this or rename it before proceeding. Exiting.\n";
        exit(1);
    }
    my $logfile = $outfile.'.log';

    open my $out, '>>', $outfile or die "\nERROR: Could not open file: $outfile\n";
    open my $log, '>>', $logfile or die "\nERROR: Could not open file: $logfile\n";

    my $genome_dir = File::Spec->catfile($path, $name.'_tephra_masked_tmp');    

    if (-d $genome_dir) {
	say "\nERROR: '$genome_dir' already exists. Please delete this or rename it before proceeding. Exiting.\n";
	exit(1);
    }
    else {
	make_path( $genome_dir, {verbose => 0, mode => 0771,} );
    }

    my $files = $self->_split_genome($genome, $genome_dir);
    die "\nERROR: No FASTA files found in genome directory. Exiting.\n" if @$files == 0;

    my $pm = Parallel::ForkManager->new($threads);
    local $SIG{INT} = sub {
        $log->warn("Caught SIGINT; Waiting for child processes to finish.");
        $pm->wait_all_children;
        exit 1;
    };

    my (@reports, $genome_length);
    $pm->run_on_finish( sub { my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $data_ref) = @_;
			      my ($report, $chr_length) = @{$data_ref}{qw(masked chrlen)};
			      $genome_length += $chr_length;
			      push @reports, $report;
			      my $t1 = gettimeofday();
                              my $elapsed = $t1 - $t0;
                              my $time = sprintf("%.2f",$elapsed/60);
                              say $log basename($ident),
                              " just finished with PID $pid and exit code: $exit_code in $time minutes";
                        } );

    for my $chr (nsort @$files) {
	my $chr_windows = $self->_split_chr_windows($chr);
	for my $wchr (@$chr_windows) {
	    $pm->start($wchr) and next;
	    $SIG{INT} = sub { $pm->finish };
	    my $mask_struct = $self->run_masking($wchr, $out);
	    
	    $pm->finish(0, $mask_struct);
	    unlink $wchr;
	}
	unlink $chr;
    }

    $pm->wait_all_children;

    $self->write_masking_results(\@reports, $genome_length, $t0);
    remove_tree( $genome_dir, { safe => 1 } );
    close $log;

    return;
}

sub run_masking {
    my $self = shift;
    my ($wchr, $out) = @_;
    my $repeatdb = $self->repeatdb;
    my $length   = $self->hitlength;

    my ($cname, $cpath, $csuffix) = fileparse($wchr, qr/\.[^.]*/);
    if ($cname =~ /(\.fa.*)/) {
	$cname =~ s/$1//;
    }

    my $chr_length = $self->get_mask_stats($wchr);

    my $report  = File::Spec->catfile($cpath, $cname.'_vmatch_report.txt');
    my $outpart = File::Spec->catfile($cpath, $cname.'_masked.fas');

    my $index = File::Spec->catfile($cpath, $cname.'.index');
    my $mkvtree_log = File::Spec->catfile($cpath, $cname.'_mkvtree_log.err');
    my $vmatch_mlog = File::Spec->catfile($cpath, $cname.'_vmatch_mask.err');
    my $vmatch_rlog = File::Spec->catfile($cpath, $cname.'_vmatch_aln.err');

    my $mkvtree = "mkvtree -db $wchr -indexname $index -dna -allout -v -pl 2>&1 > $mkvtree_log";
    my $vmatchm = "vmatch -p -d -q $repeatdb -qspeedup 2 -l $length -best 10000 -identity 80 -dbmaskmatch N $index 1> $outpart 2> $vmatch_mlog";
    my $vmatchr = "vmatch -p -d -q $repeatdb -qspeedup 2 -l $length -best 10000 -sort ia -identity 80 -showdesc 0 $index 1> $report 2> $vmatch_rlog";

    $self->run_cmd($mkvtree); # need to warn here, not just log errors
    $self->run_cmd($vmatchm);
    $self->run_cmd($vmatchr);

    my $mask_struct = $self->get_masking_results($wchr, $report, $chr_length);

    $self->clean_index($index);
    $self->collate($outpart, $out);
    unlink $outpart, $mkvtree_log, $vmatch_mlog; #, $vmatch_rlog;

    return { masked => $mask_struct, chrlen => $chr_length };
}

sub get_masking_results {
    my $self = shift;
    my ($chr, $voutfile, $genome_length) = @_;
    my $genome  = $self->genome;
    my $outfile = $self->outfile;

    my $repeat_map = $self->_build_repeat_map;

    open my $in, '<', $voutfile or die "\nERROR: Could not open file: $voutfile\n";
    
    my (%windows, %refs, %hits, %aligns, %report, %final_rep);

    my $tree = Set::IntervalTree->new;
    my $comm = <$in>; # discard the args to vmatch
    my $line = <$in>;
    unless (defined $line && $line =~ /\S/) {
	# if no hits, return
	close $in;
	unlink $voutfile;
	return \%report;
    }
    # $line is the following format: 
    # l(S) h(S) r(S) t l(Q) h(Q) r(Q) d e s i
    # where:
    # l = length
    # h = sequence header
    # r = relative position
    # t = type (D=direct, P=palindromic)
    # d = distance value (negative=hamming distance, 0=exact, positive=edit distance)
    # e = E-value
    # s = score value (negative=hamming score, positive=edit score)
    # i = percent identity
    # (S) = in Subject
    # (Q) = in Query
    chomp $line;
    $line =~ s/^\s+//;
    my @f = split /\s+/, $line;
    my $send = $f[2] + $f[0];
    $tree->insert({ id => $f[1], match => $f[5], start => $f[2], end => $send, len => $f[0] }, $f[2], $send);
    $windows{$f[2]} = { start => $f[2], end => $send, len => $f[0], overlap => 0, match => $f[5] };

    while (my $line = <$in>) {
	chomp $line;
	$line =~ s/^\s+//;
	my ($slen, $sid, $spos, $htype, $qlen, $hid, $qpos, $dist, $evalue, $score, $pid) = split /\s+/, $line;
	my $end = $spos + $slen;

	my $res = $tree->fetch($spos, $end);
    
	if (@$res) {
	    my ($best_start, $best_end, $overl, $best_match);
	    for my $overlap (@$res) {           
		my ($ostart, $oend, $match, $subj, $olen) = @{$overlap}{qw(start end match id len)};

		$best_start = $ostart <= $spos ? $ostart : $spos;
		$best_end = $oend >= $end ? $oend : $end;
		my $oe = $best_end == $oend ? $end : $oend;
		$overl = $best_end - $oe;

		$tree->remove($ostart, $oend);
	    }
        
	    my $nlen = $best_start > 0 ? $best_end-$best_start : $best_end;
	    $windows{$best_start} = { start => $best_start, end => $best_end, len => $nlen, match => $hid, overlap => $overl };
	    $tree->insert({ id => $sid, match => $hid, start => $best_start, end => $best_end, len => $nlen }, $best_start, $best_end);
	}
	else {
	    $tree->insert({ id => $sid, match => $hid, start => $spos, end => $end, len => $slen }, $spos, $end);
	    $windows{$spos} = { start => $spos, end => $end, len => $slen, overlap => 0, match => $hid};
	}
    }
    close $in;
    
    for my $s (sort { $a <=> $b } keys %windows) {
	if (exists $windows{ $windows{$s}{end} }) {
	    my $h = $windows{ $windows{$s}{end} };
	    $windows{ $windows{$s}{end} } = { start   => $h->{start}+1, 
					      end     => $h->{end},
					      match   => $h->{match},
					      len     => $h->{len}-1,
					      overlap => 0 };
	}
    }

    for my $s (sort { $a <=> $b } keys %windows) { 
	my ($code) = ($windows{$s}{match} =~ /^(\w{3})-?_?/);         
	if (defined $code && exists $repeat_map->{$code}) {
	    push @{$report{ $code }}, $windows{$s}{len};
	}
    }

    #unlink $voutfile;
    return \%report;
}

sub write_masking_results {
    my $self = shift;
    my ($reports, $genome_length, $t0) = @_;
    my $genome  = $self->genome;
    my $outfile = $self->outfile;

    my %final_rep;
    my $repeat_map = $self->_build_repeat_map;

    my ($classlen, $orderlen, $namelen, $masklen);
    for my $report (@$reports) {
	next unless %$report;
	for my $rep_type (keys %$report) {
            my $total = sum(@{$report->{$rep_type}});
            my ($class, $order, $name) = @{$repeat_map->{$rep_type}}{qw(class order repeat_name)};
            ($classlen, $orderlen, $namelen) = (length($class), length($order), length($name)); 
            $final_rep{$class}{$order}{$name} += $total;
        }
    }
    
    my $t2 = gettimeofday();
    my $total_elapsed = $t2 - $t0;
    my $final_time = sprintf("%.2f",$total_elapsed/60);

    ($classlen,$orderlen, $namelen) = ($classlen+10, $orderlen+10, $namelen+15);
    my $masked_total = 0;
    say "=================== 'Tephra maskref' finished in $final_time minutes =================";
    printf "%-${classlen}s %-${classlen}s %-${orderlen}s %-${namelen}s\n", "Class", "Order", "Superfamily", "Percent Masked";

    say "-" x 80;
    for my $class (sort keys %final_rep) {
        for my $order (sort keys %{$final_rep{$class}}) {
            for my $name (sort keys %{$final_rep{$class}{$order}}) {
                $masked_total += $final_rep{$class}{$order}{$name};
                my $repmasked = sprintf("%.2f",($final_rep{$class}{$order}{$name}/$genome_length)*100);
                printf "%-${classlen}s %-${classlen}s %-${orderlen}s %-${namelen}s\n",
		    $class, $order, $name, "$repmasked% ($final_rep{$class}{$order}{$name}/$genome_length)";
            }
        }
    }

    my $masked = sprintf("%.2f",($masked_total/$genome_length)*100);
    say "=" x 80;
    say "Input file:          $genome";
    say "Output file:         $outfile";
    say "Total genome length: $genome_length";
    say "Total masked bases:  $masked% ($masked_total/$genome_length)";

    return;
}

sub collate {
    my $self = shift;
    my ($file_in, $fh_out) = @_;
    
    open my $fh_in, '<', $file_in or die "\nERROR: Could not open file: $file_in\n";

    while (my $line = <$fh_in>) {
	chomp $line;
	say $fh_out $line;
    }
}

sub clean_index {
    my $self = shift;
    my ($index) = @_;
    
    my ($name, $path, $suffix) = fileparse($index, qr/\.[^.]*/);

    my $pat;
    for my $suf (qw(.al1 .llv .ssp .bck .ois .sti1 .bwt .prj .suf .des .sds .tis .lcp .skp)) {
	$pat .= "$name$suffix$suf|";
    }
    $pat =~ s/\|$//;

    my @files;
    find( sub { push @files, $File::Find::name if /$pat/ }, $path);

    unlink @files;
    return;
}

sub get_mask_stats {
    my $self = shift;
    my ($genome) = @_;

    my $kseq = Bio::DB::HTS::Kseq->new($genome);
    my $iter = $kseq->iterator;

    my $total;
    while (my $seqobj = $iter->next_seq) {
	my $name = $seqobj->name;
	my $seq  = $seqobj->seq;
	my $seqlength = length($seq);
	if ($seqlength > 0) {
	    $total += $seqlength;
	}
    }

    return $total;
}

sub _split_genome {
    my $self = shift;
    my ($genome, $genome_dir) = @_;

    my @files;
    my $kseq = Bio::DB::HTS::Kseq->new($genome);
    my $iter = $kseq->iterator;
    while (my $seqobj = $iter->next_seq) {
	my $id = $seqobj->name;
	my $dir = File::Spec->catdir($genome_dir, $id);
	make_path( $dir, {verbose => 0, mode => 0771,} );
	my $outfile = File::Spec->catfile($dir, $id.'.fasta');
	open my $out, '>', $outfile or die "\nERROR: Could not open file: $outfile\n";
	say $out join "\n", ">".$id, $seqobj->seq;
	close $out;
	push @files, $outfile;
    }
    
    return \@files;
}

sub _split_chr_windows {
    my $self = shift;
    my ($genome) = @_;
    my $split_size = $self->splitsize;

    my ($name, $path, $suffix) = fileparse($genome, qr/\.[^.]*/);

    my @split_files;
    my $remainder = 0;
    my $kseq = Bio::DB::HTS::Kseq->new($genome);
    my $iter = $kseq->iterator;

    while (my $seqobj = $iter->next_seq) {
	my $id  = $seqobj->name;
	my $seq = $seqobj->seq;
	my $length = length($seq);
	$remainder = $length;
	my ($total, $start) = (0, 0);
	my $steps = sprintf("%.0f", $length/$split_size);

	for my $i (0..$steps) {
	    if ($remainder < $split_size) {
		$split_size = $remainder; # if $remainder < $split_size;
		my $seq_part = substr $seq, $start, $split_size;
		$seq_part =~ s/.{60}\K/\n/g;
		my $outfile = File::Spec->catfile($path, $id."_$i.fasta");
		open my $out, '>', $outfile or die "\nERROR: Could not open file: $outfile\n";
		say $out join "\n", ">".$id."_$i", $seq_part;
		close $out;
		push @split_files, $outfile;
		last;
	    }
	    else {
		my $seq_part = substr $seq, $start, $split_size;
                $seq_part =~ s/.{60}\K/\n/g;
                my $outfile = File::Spec->catfile($path, $id."_$i.fasta");
                open my $out, '>', $outfile or die "\nERROR: Could not open file: $outfile\n";
                say $out join "\n", ">".$id."_$i", $seq_part;
                close $out;
		push @split_files, $outfile;
	    }

	    $start += $split_size;
	    $remainder -= $split_size;
	    $i++;
	}
    }

    return \@split_files;
}

sub _build_repeat_map {
    my $self = shift;

    my %repeat_map = (
	## Class I
	# DIRS
	'RLD' => { class => 'Class I', order => 'DIRS', repeat_name => 'DIRS' },
	'RYN' => { class => 'Class I', order => 'DIRS', repeat_name => 'Ngaro' },
	'RYX' => { class => 'Class I', order => 'DIRS', repeat_name => 'Unknown DIRS' },
	'RYV' => { class => 'Class I', order => 'DIRS', repeat_name => 'VIPER' },
	# LINE 
	'RII' => { class => 'Class I', order => 'LINE', repeat_name => 'I' },
	'RIJ' => { class => 'Class I', order => 'LINE', repeat_name => 'Jockey' },
	'RIL' => { class => 'Class I', order => 'LINE', repeat_name => 'L1' },
	'RIR' => { class => 'Class I', order => 'LINE', repeat_name => 'R2' },
	'RIT' => { class => 'Class I', order => 'LINE', repeat_name => 'RTE' },
	'RIX' => { class => 'Class I', order => 'LINE', repeat_name => 'Unknown LINE' },
	'RIC' => { class => 'Class I', order => 'LINE', repeat_name => 'CR1' },
	# LTR
	'RLB' => { class => 'Class I', order => 'LTR', repeat_name => 'Bel/Pao' },
	'RLC' => { class => 'Class I', order => 'LTR', repeat_name => 'Copia' },
	'RLE' => { class => 'Class I', order => 'LTR', repeat_name => 'ERV' },
	'RLG' => { class => 'Class I', order => 'LTR', repeat_name => 'Gypsy' },
	'RLR' => { class => 'Class I', order => 'LTR', repeat_name => 'Retrovirus' },
	'RLT' => { class => 'Class I', order => 'LTR', repeat_name => 'TRIM' },
	'RLX' => { class => 'Class I', order => 'LTR', repeat_name => 'Unknown LTR' },
	# PLE
	'RPP' => { class => 'Class I', order => 'Penelope', repeat_name => 'Penelope' },
	'RPX' => { class => 'Class I', order => 'Penelope', repeat_name => 'Unknown PLE' },
	# SINE
	'RSS' => { class => 'Class I', order => 'SINE', repeat_name => '5S' },
	'RSL' => { class => 'Class I', order => 'SINE', repeat_name => '7SL' },
	'RST' => { class => 'Class I', order => 'SINE', repeat_name => 'tRNA' },
	'RSX' => { class => 'Class I', order => 'SINE', repeat_name => 'Unknown SINE' },
	'RXX' => { class => 'Class I', order => 'SINE', repeat_name => 'Unknown retrotransposon' },
	## Class II
	# - Subclass 1
	# Crypton
	'DYC' => { class => 'Class II', order => 'Crypton', repeat_name => 'Crypton' },
	'DYX' => { class => 'Class II', order => 'Crypton', repeat_name => 'Unknown Crypton' },
	# TIR
	'DTC' => { class => 'Class II', order => 'TIR', repeat_name => 'CACTA' },
	'DTA' => { class => 'Class II', order => 'TIR', repeat_name => 'hAT' },
	'DTE' => { class => 'Class II', order => 'TIR', repeat_name => 'Merlin' },
	'DTM' => { class => 'Class II', order => 'TIR', repeat_name => 'Mutator' },
	'DTP' => { class => 'Class II', order => 'TIR', repeat_name => 'P' },
	'DTH' => { class => 'Class II', order => 'TIR', repeat_name => 'PIF/Harbinger' },
	'DTB' => { class => 'Class II', order => 'TIR', repeat_name => 'PiggyBac' },
	'DTT' => { class => 'Class II', order => 'TIR', repeat_name => 'Tc1/Mariner' },
	'DTR' => { class => 'Class II', order => 'TIR', repeat_name => 'Transib' },
	'DTX' => { class => 'Class II', order => 'TIR', repeat_name => 'Unknown TIR' },
	'DXX' => { class => 'Class II', order => 'TIR', repeat_name => 'Unknown DNA transposon' },
	# - Subclass 2
	# Helitron
	'DHH' => { class => 'Class II', order => 'Helitron', repeat_name => 'Helitron' },
	'DHX' => { class => 'Class II', order => 'Helitron', repeat_name => 'Unknown Helitron' },
	# Maverick
	'DMM' => { class => 'Class II', order => 'Maverick', repeat_name => 'Maverick' },
	'DMX' => { class => 'Class II', order => 'Maverick', repeat_name => 'Unknown Maverick' },
	);

    return \%repeat_map;
}

=head1 AUTHOR

S. Evan Staton, C<< <statonse at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests through the project site at 
L<https://github.com/sestaton/tephra/issues>. I will be notified,
and there will be a record of the issue. Alternatively, I can also be 
reached at the email address listed above to resolve any questions.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Tephra::Genome::MaskRef


=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015- S. Evan Staton

This program is distributed under the MIT (X11) License, which should be distributed with the package. 
If not, it can be found here: L<http://www.opensource.org/licenses/mit-license.php>

=cut

__PACKAGE__->meta->make_immutable;

1;
