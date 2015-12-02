package Tephra::Command::findltrs;
# ABSTRACT: Find LTR retrotransposons in a genome assembly.

use 5.010;
use strict;
use warnings;
use File::Find;
use File::Basename;
use Tephra -command;
use Tephra::LTR::LTRSearch;
use Tephra::LTR::LTRRefine;

sub opt_spec {
    return (    
	[ "genome|g=s",   "The genome sequences in FASTA format to search for LTR-RTs "    ],
	[ "trnadb|t=s",   "The file of tRNA sequences in FASTA format to search for PBS "  ], 
	[ "hmmdb|d=s",    "The HMM db in HMMERv3 format to search for coding domains "     ],
	[ "outfile|o=s",  "The final combined and filtered GFF3 file of LTR-RTs "          ],
	[ "index|i=s",    "The suffixerator index to use for the LTR search "              ],
	[ "mintsd=i",     "The minimum TSD length (Default: 4) "                           ],
	[ "maxtsd=i",     "The maximum TSD length (Default: 6) "                           ],
	[ "minlenltr=i",  "The minimum LTR length (Default: 100) "                         ],
	[ "maxlenltr=i",  "The maximum LTR length (Default: 6000) "                        ],
	[ "mindistltr=i", "The minimum LTR element length (Default: 1500) "                ],
	[ "maxdistltr=i", "The maximum LTR element length (Default: 25000) "               ],
	[ "dedup|r",      "Discard elements with duplicate coding domains (Default: no) "  ],
	[ "tnpfilter",    "Discard elements containing transposase domains (Default: no) " ],
	[ "clean|c",      "Clean up the index files (Default: yes) "                       ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;

    my $command = __FILE__;
    if ($self->app->global_options->{man}) {
	system([0..5], "perldoc $command");
    }
    elsif ($self->app->global_options->{help}) {
	$self->help;
    }
    elsif (!$opt->{genome} || !$opt->{hmmdb} || !$opt->{trnadb}) {
	say "\nERROR: Required arguments not given.";
	$self->help and exit(0);
    }
    elsif (! -e $opt->{genome}) { 
	say "\nERROR: '--genome' file given but does not appear to exist. Check input.";
	$self->help and exit(0);
    }
    elsif (! -e $opt->{hmmdb}) { 
	say "\nERROR: '--hmmdb' file given but does not appear to exist. Check input.";
	$self->help and exit(0);
    }
    elsif (! -e $opt->{trnadb}) { 
	say "\nERROR: '--trnadb' file given but does not appear to exist. Check input.";
	$self->help and exit(0);
    }
} 

sub execute {
    my ($self, $opt, $args) = @_;

    exit(0) if $self->app->global_options->{man} ||
	$self->app->global_options->{help};

    my ($relaxed_gff, $strict_gff) = _run_ltr_search($opt);
    my $some = _refine_ltr_predictions($relaxed_gff, $strict_gff, $opt);
}

sub _refine_ltr_predictions {
    my ($relaxed_gff, $strict_gff, $opt) = @_;

    my %refine_opts = (
	genome => $opt->{genome}, 
    );

    if (defined $opt->{outfile}) {
	$refine_opts{outfile} = $opt->{outfile};
    }

    $refine_opts{remove_dup_domains} = $opt->{dedup} // 0;
    $refine_opts{remove_tnp_domains} = $opt->{tnpfilter} // 0;

    my $refine_obj = Tephra::LTR::LTRRefine->new(%refine_opts);

    if (defined $relaxed_gff && defined $strict_gff) {
	my $relaxed_features
	    = $refine_obj->collect_features({ gff => $relaxed_gff, pid_threshold => 85 });
	my $strict_features
	    = $refine_obj->collect_features({ gff => $strict_gff,  pid_threshold => 99 });
	
	my $best_elements = $refine_obj->get_overlaps({ relaxed_features => $relaxed_features, 
							strict_features  => $strict_features });
	
	my $combined_features = $refine_obj->reduce_features({ relaxed_features => $relaxed_features, 
							       strict_features  => $strict_features,
							       best_elements    => $best_elements });
	
	$refine_obj->sort_features({ gff               => $relaxed_gff, 
				     combined_features => $combined_features });
    }
    elsif (defined $relaxed_gff && !defined $strict_gff) {
	say STDERR "\nWARNING: No LTR retrotransposons were found under strict conditions. ".                  
            "Skipping refinement step.\n";
	$refine_obj->sort_features({ gff               => $relaxed_gff,
                                     combined_features => undef });
    }
    else {
	say STDERR "\nWARNING: No LTR retrotransposons were found with the given parameters.\n";
    }
}
    
sub _run_ltr_search {
    my ($opt) = @_;
    
    $opt->{clean}  //= 0;

    my @indexfiles;
    if (defined $opt->{index}) {
	my ($name, $path, $suffix) = fileparse($opt->{index}, qr/\.[^.]*/);
	my @files;
	for my $suf ('.des', '.lcp', '.llv', '.md5', '.prj', '.sds', '.suf')  {
	    push @files, $opt->{index}.$suf;
	}
	
	my $matchstr = join "|", @files;
	find( sub { push @indexfiles, $File::Find::name if -f and /$matchstr/ }, $path );
    }

    my $ltr_search = Tephra::LTR::LTRSearch->new( 
	genome => $opt->{genome}, 
	hmmdb  => $opt->{hmmdb},
	trnadb => $opt->{trnadb}, 
	clean  => $opt->{clean} 
    );

    unless (defined $opt->{index} && @indexfiles == 7) {
	my ($name, $path, $suffix) = fileparse($opt->{genome}, qr/\.[^.]*/);
	$opt->{index} = $opt->{genome}.".index";
    
	my @suff_args = qq(-db $opt->{genome} -indexname $opt->{index} -tis -suf -lcp -ssp -sds -des -dna);
	$ltr_search->create_index(\@suff_args);
    }
    
    my $strict_gff  = $ltr_search->ltr_search_strict($opt->{index});
    my $relaxed_gff = $ltr_search->ltr_search_relaxed($opt->{index});

    return ($relaxed_gff, $strict_gff);
}

sub help {
    print STDERR<<END

USAGE: tephra findltrs [-h] [-m]
    -m --man      :   Get the manual entry for a command.
    -h --help     :   Print the command usage.

Required:
    -g|genome     :   The genome sequences in FASTA format to search for LTR-RTs. 
    -t|trnadb     :   The file of tRNA sequences in FASTA format to search for PBS. 
    -d|hmmdb      :   The HMM db in HMMERv3 format to search for coding domains.

Options:
    -o|outfile    :   The final combined and filtered GFF3 file of LTR-RTs.
    -i|index      :   The suffixerator index to use for the LTR search.
    --mintsd      :   The minimum TSD length (Default: 4).
    --maxtsd      :   The maximum TSD length (Default: 6).
    --minlenltr   :   The minimum LTR length (Default: 100).
    --maxlenltr   :   The maximum LTR length (Default: 6000).
    --mindistltr  :   The minimum LTR element length (Default: 1500).
    --maxdistltr  :   The maximum LTR element length (Default: 25000).
    -r|dedup      :   Discard elements with duplicate coding domains (Default: no).
    --tnpfilter   :   Discard elements containing transposase domains (Default: no).
    -c|clean      :   Clean up the index files (Default: yes).

END
}


1;
__END__

=pod

=head1 NAME
                                                                       
 tephra findltrs - Find LTR retrotransposons in a genome assembly.

=head1 SYNOPSIS    

 tephra findltrs -g ref.fas -t trnadb.fas -d te_models.hmm --tnpfilter --clean

=head1 DESCRIPTION
 
 Search a reference genome and find LTR-RTs under relaxed and strict conditions (more on
 this later...), filter all predictions by a number of criteria, and generate a consensus
 set of the best scoring elements.

=head1 AUTHOR 

S. Evan Staton, C<< <statonse at gmail.com> >>

=head1 REQUIRED ARGUMENTS

=over 2

=item -g, --genome

 The genome sequences in FASTA format used to search for LTR-RTs.

=item -t, --trnadb

 The file of tRNA sequences in FASTA format to search for PBS.

=item -d, --hmmdb

 The HMM db in HMMERv3 format to search for coding domains.

=back

=head1 OPTIONS

=over 2

=item -o, --outfile

 The final combined and filtered GFF3 file of LTR-RTs.

=item -i, --index

 The suffixerator index to use for the LTR search.

=item --mintsd

 The minimum TSD length (Default: 4).

=item --maxtsd

 The maximum TSD length (Default: 6).

=item --minlenltr

 The minimum LTR length (Default: 100).

=item --maxlenltr

  The maximum LTR length (Default: 6000).

=item --mindistltr

 The minimum LTR element length (Default: 1500).

=item --maxdistltr

 The maximum LTR element length (Default: 25000).

=item -r, --dedup

 Discard elements with duplicate coding domains (Default: no).

=item --tnpfilter

 Discard elements containing transposase domains (Default: no).

=item -c, --clean

 Clean up the index files (Default: yes).

=item -h, --help

 Print a usage statement. 

=item -m, --man

 Print the full documentation.

=back

=cut
