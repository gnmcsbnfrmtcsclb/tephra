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

use Test::More tests => 4;

$| = 1;

my $devtests = 0;
if (defined $ENV{TEPHRA_ENV} && $ENV{TEPHRA_ENV} eq 'development') {
    $devtests = 1;
}

my $cmd     = File::Spec->catfile('blib', 'bin', 'tephra');
my $testdir = File::Spec->catdir('t', 'test_data');
my $genome  = File::Spec->catfile($testdir, 'ref.fas');
my $gff     = File::Spec->catfile($testdir, 'ref_tirs_classified.gff3');
my $outdir  = File::Spec->catdir($testdir,  'ref_tirs_classified_tirages');

SKIP: {
    skip 'skip development tests', 4 unless $devtests;
    {
        my @help_args = ($cmd, 'tirage', '-h');
        my ($stdout, $stderr, $exit) = capture { system(@help_args) };
        #say STDERR "stderr: $stderr";
        ok($stderr, 'Can execute tirage subcommand');
    }

    my $outfile = $gff;
    $outfile =~ s/\.gff3/_tirages.tsv/;
    my @age_cmd = ($cmd, 'tirage', '-g', $genome, '-f', $gff, '-o', $outfile, '--all');
    #say STDERR $age_cmd;
    my @ret = capture { system([0..5], @age_cmd) };

    ok( -s $outfile, 'Generated TIR age report for input GFF3 file');

    open my $in, '<', $outfile;
    my $h = <$in>;
    my $ct = 0;
    ++$ct while <$in>;
    close $in;
    ok( $ct == 1, 'Expected number of entries in TIR age report');

    my @resdirs;
    find( sub { push @resdirs, $File::Find::name if -d and /tirages/ }, $testdir);
    ok( @resdirs == 1, 'Generated the expected number of TIR age calculations');
    
    ## clean up
    my @outfiles;
    find( sub { push @outfiles, $File::Find::name if /^ref_tirs/ }, $testdir);
    unlink @outfiles;

    remove_tree( $outdir, { safe => 1 } );
};

unlink $gff if -e $gff;
done_testing();
