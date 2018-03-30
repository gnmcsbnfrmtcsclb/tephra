#!/usr/bin/env perl

use 5.010;
use strict;
use warnings FATAL => 'all';
use autodie             qw(open);
use IPC::System::Simple qw(system);
use Capture::Tiny       qw(capture);
use File::Find;
use File::Spec;

use Test::More tests => 14;

$| = 1;

my $devtests = 0;
if (defined $ENV{TEPHRA_ENV} && $ENV{TEPHRA_ENV} eq 'development') {
    $devtests = 1;
}

my $cmd     = File::Spec->catfile('blib', 'bin', 'tephra');
my $testdir = File::Spec->catdir('t', 'test_data');
my $genome  = File::Spec->catfile($testdir, 'Ha1.fa');
my $outfile = File::Spec->catfile($testdir, 'Ha1_combined_trims.gff3');
my $outfas  = File::Spec->catfile($testdir, 'Ha1_combined_trims.fasta');
my $log     = File::Spec->catfile($testdir, 'Ha1_tephra_findtrims.log');

## these are subsets for testing
#my $model   = File::Spec->catfile($testdir, 'te.hmm');
#my $trnas   = File::Spec->catfile($testdir, 'trnas.fas');

{
    my @help_args = ($cmd, 'findtrims', '-h');
    my ($stdout, $stderr, $exit) = capture { system(@help_args) };
        #say STDERR "stderr: $stderr";
    ok($stderr, 'Can execute findtrims subcommand');
}

SKIP: {
    skip 'skip development tests', 13 unless $devtests;

    my @find_cmd = ($cmd, 'findtrims', '-g', $genome, '-o', $outfile, '--clean');
    say STDERR join q{ }, @find_cmd;
    #system([0..5], $find_cmd);
    my ($stdout, $stderr, @ret) = capture { system([0..5], @find_cmd) };
    
    for my $line (split /^/, $stderr) {
	if ($line =~ /length_filtered/) {
	    my ($l_filt) = $line =~ /(\d+)$/;
	    say STDERR "l_filt: $l_filt exp: 0";
	    ok( $l_filt == 0, 'Correct number of elements filtered by length' );
	}
	if ($line =~ /compound_gyp_cop_filtered/) {
	    my ($gc_filt) = $line =~ /(\d+)$/;
	    say STDERR "gc_filt: $gc_filt";
	    ok( $gc_filt == 0, 'Correct number of elements filtered compound gypsy/copia' );
	}
	if ($line =~ /n_perc_filtered/) {
	    my ($n_filt) = $line =~ /(\d+)$/;
	    ok( $n_filt == 43, 'Correct number of elements filtered by N-percentage' );
	}
	elsif ($line =~ /\'relaxed\' constraints/) {
	    my ($r_ct) = $line =~ /(\d+)$/;
	    say STDERR "r_ct: $r_ct exp: 757";
	    ok( $r_ct == 757, 'Correct number of combined elements found by relaxed constraints' );
	}
	elsif ($line =~ /\'strict\' constraints/) {
	    my ($s_ct) = $line =~ /(\d+)$/;
	    say STDERR "s_ct: $s_ct exp: 0";
	    ok( $s_ct == 0, 'Correct number of total elements found by strict constraints' );
	}
	elsif ($line =~ /\'best\'/) {
	    my ($b_ct) = $line =~ /(\d+)$/;
	    say STDERR "b_ct: $b_ct exp: 7";
	    ok( $b_ct == 7, 'Correct number of best elements found' );
	}
	elsif ($line =~ /\'combined\'/) {
	    my ($c_ct) = $line =~ /(\d+)$/;
	    say STDERR "c_ct: $c_ct exp: 721";
	    ok( $c_ct == 721, 'Correct number of combined elements found' );
	}
	elsif ($line =~ /Total elements written/) {
	    my ($t_ct) = $line =~ /(\d+)$/;
	    say STDERR "t_ct: $t_ct exp: 721";
	    ok( $t_ct == 721, 'Correct number of total elements found' );
	}
    }

    open my $in, '<', $outfas;
    my $ct = 0;
    while (<$in>) { $ct++ if /^>/; }
    close $in;
    
    ok( $ct == 721,  'Correct number of TRIMs in output FASTA file' );
    ok( -e $outfile, 'Created TRIMs in output GFF3 file'            );
    
    open my $gin, '<', $outfile;
    my $gct = 0;
    while (<$gin>) {
	chomp;
	next if /^#/;
	my @f = split /\t/;
	$gct++ if $f[2] eq 'TRIM_retrotransposon';
    }
    close $gin;
    
    ok( $gct == 721,  'Correct number of TRIMs in output GFF3 file'        );
    ok( $ct == $gct,  'Expected number of records in GFF3 and FASTA files' );
    ok( -e $log,      'Expected log file of TRIM results produced'         );
    
    ## clean up
    unlink $outfile, $outfas, $log;
}

done_testing();
