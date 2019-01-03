#!/usr/bin/env perl

use 5.010;
use strict;
use warnings FATAL => 'all';
use autodie             qw(open);
use IPC::System::Simple qw(system);
use Capture::Tiny       qw(capture);
use File::Path          qw(remove_tree);
use File::Find;
use File::Spec;

use Test::More tests => 6;

$| = 1;

my $devtests = 0;
if (defined $ENV{TEPHRA_ENV} && $ENV{TEPHRA_ENV} eq 'development') {
    $devtests = 1;
}

my $cmd      = File::Spec->catfile('blib', 'bin', 'tephra');
my $testdir  = File::Spec->catdir('t', 'test_data');
my $genome   = File::Spec->catfile($testdir, 'ref.fas');
my $ingff    = File::Spec->catfile($testdir, 'ref_tirs.gff3');
my $outgff   = File::Spec->catfile($testdir, 'ref_tirs_classified.gff3');
my $outfas   = File::Spec->catfile($testdir, 'ref_tirs_classified.fasta');
my $log      = File::Spec->catfile($testdir, 'ref_tephra_classifytirs.log');
my $outdir   = File::Spec->catfile($testdir, 'tir_family_domains');
my $repeatdb = File::Spec->catfile($testdir, 'repdb.fas');

{
    my @help_args = ($cmd, 'classifytirs', '-h');
    my ($stdout, $stderr, $exit) = capture { system(@help_args) };
    #say STDERR "stderr: $stderr";
    ok($stderr, 'Can execute classifytirs subcommand');
}

if ($devtests) {
    $genome   = File::Spec->catfile($testdir, 'TAIR10_chr1.fas');
    $ingff    = File::Spec->catfile($testdir, 'TAIR10_chr1_tirs.gff3');
    $outgff   = File::Spec->catfile($testdir, 'TAIR10_chr1_tirs_classified.gff3');
    $outfas   = File::Spec->catfile($testdir, 'TAIR10_chr1_tirs_classified.fasta');
    $log      = File::Spec->catfile($testdir, 'TAIR10_chr1_tephra_classifytirs.log');
    $repeatdb = File::Spec->catfile($testdir, 'RepBase1801_arab.fasta');
}

my @find_cmd = ($cmd, 'classifytirs', '-g', $genome, '-d', $repeatdb, '-i', $ingff, '-o', $outgff, '-r', $outdir);
#say STDERR join q{ }, @find_cmd;
my @ret = capture { system([0..5], @find_cmd) };

ok( -e $outgff, 'Correctly classified TIRs' );
ok( -e $outfas, 'Correctly classified TIRs' );

my $seqct = 0;
open my $in, '<', $outfas;
while (<$in>) { $seqct++ if /^>/; }
close $in;

my $gffct = 0;
open my $gin, '<', $outgff;
while (<$gin>) { 
    chomp;
    next if /^#/;
    my @f = split /\t/;
    $gffct++ if $f[2] =~ /terminal_inverted_repeat_element|MITE/;
}
close $gin;

if ($devtests) {
    #say STDERR join q{ }, $seqct, $gffct;
    ok( $seqct == 270, 'Correct number of TIRs classified' );
    ok( $gffct == 270, 'Correct number of TIRs classified' );
    ok( -e $log, 'Correctly logged TIR classification results' );
}
else { 
    ok( $seqct == 1, 'Correct number of TIRs classified' );
    ok( $gffct == 1, 'Correct number of TIRs classified' );
    ok( -e $log, 'Correctly logged TIR classification results' );
}

## clean up
my @dom_orgs;
find( sub { push @dom_orgs, $File::Find::name if -f and /tirs.*domain_org.tsv$/ }, $testdir );
unlink @dom_orgs;
unlink $outfas, $log;
unlink $ingff;
remove_tree( $outdir, { safe => 1 } );

done_testing();
