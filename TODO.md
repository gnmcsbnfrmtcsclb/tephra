# TEPHRA TODO

This file is for logging feature requests and bugs during development. Hopefully, having one list will make it easier to keep track of proposed changes. It would be nice to rank the lists in order to prioritize tasks. It should be noted this list is for development purposes and it may go away once a stable release is made.

## Command `tephra classifyltrs`
 - [x] Classify 'best' LTR-RT elements into superfamilies based on domain content and organization
 - [x] Classify elements into families based on cluster organization; Generate FASTA for each family
 - [x] Create singletons file of ungrouped LTR-RT sequences
 - [x] Create FASTA files of exemplars for each LTR-RT family
 - [x] clean up logs and intermediate files from vmatch (dbluster-*)
 - [x] combine domain organization from both strands (if the same)?
 - [x] add family classifications to GFF Name attribute
 - [x] incorporate legacy annotations from input GFF/reference to family classification
 - [x] merge overlapping hits in chain of protein matches, and contatenate the rest for each element
 - [x] mark unclassified elements with no protein domains as LARDs
 - [x] combine exemplars for efficiently comparing to a reference set
 - [x] identify fragmented elements with refined full-length elements (handled in v0.08.0+ in 'getfragments'
       command)
 - [x] include measure of similarity within/between families
 - [x] use BLAST role to run searches for 'search_unclassified' method in Tephra::Classify::LTRSfams
 - [x] investigate why UBN2* domains are being used to classify Gypsy (modified regex in v0.17.7 should solve the problem; 
       need to do full-genome test to confirm)
 - [ ] add DIRS and PLE so we are describing all orders in Wicker's scheme
 - [x] LARD annotation method not working for GFF3 as of v0.11.0
 - [x] Family number in FASTA/GFF3 not aligned with that in domain organization file
 - [x] Domain order is incorrect in family-level domain classication file as of v0.11.0

## Command `tephra findtirs`
 - [x] Find all non-overlapping TIR elements passing thresholds
 - [x] Generate combined GFF3 of high-quality TIRs
 - [x] Check for index (if given)
 - [x] Add optional test for the presence of coding domains similar to 'LTRRefine' class. This should reduce the
       number of DTX elements. Add this to the configuration file for the 'all' command the same as for LTRs.
 - [x] Mark short elements with no coding potential as MITEs
 - [x] Output FASTA along with GFF3 like other commands

## Command `tephra sololtr`
 - [x] Create HMM of LTRs for each LTR-RT
 - [x] Search masked ref with LTR HMM
 - [x] Create GFF with SO terms of solo-LTRs
 - [x] parallelize hmmsearch to speed things up. likely this is faster than multiple cpus for one model at time
 - [x] check if input directory exists
 - [x] make sure to set path to correct version of hmmer
 - [x] add family name to GFF output (the family name is now in the Parent tag)
 - [x] add option to pick on the top 20 families to speed up execution
 - [x] consider preprocessing all LTR files so we don't block on one superfamily waiting for threads to finish
 - [x] if the soloLTR sequence file is empty, delete all other files and warn no soloLTRs were found
 - [x] evaluate search results as the process completes so the number of (potentially empty) files does not
       grow too large

## Command `tephra classifytirs`
 - [x] Classify 'best' TIR elements into superfamilies based on domain content, TSD, and/or motif
 - [x] Group TIR elements into families based on TIR similarity and/or cluster-based method used for LTR-RT classification 
 - [x] in tests, skip if empty output (none found). This is not a good test honestly, need a new reference
 - [x] write fasta of each superfamily, and combined library
 - [x] identify	fragmented elements with refined full-length elements
 - [x] report domain architecture, as for LTR elements
 - [x] add MITE annotation to GFF3
 - [x] add MITE annotation to FASTA

## Command `tephra findltrs`
 - [x] Find all non-overlapping LTR-RTs under strict and relaxed conditions
 - [x] Filter elements by quality score, retaining the best elements
 - [x] Generate combined GFF3 of high-quality LTR-RTs
 - [x] Check for index (if given)
 - [x] change header format to be ">id_source_range"
 - [x] adjust filtering command to not increment if element has been deleted (inflated filtering stats)
 - [x] reporting of superfamilies after ltr search?.. better to do that at classification stage
 - [x] add options for LTR size parameters
 - [ ] add LTR_Finder (caveat: seems too slow in preliminary tests, probably better to continue refining
       the current methods)
 - [x] add config file to handle the multitude of LTR-RT constraints
 - [x] clean up ltrharvest and ltrdigest intermediate files
 - [x] Add optional test for the presence of coding domains to 'LTRRefine' class. This should reduce the
       number of RLX elements.
 - [ ] flag suspicious compound elements somehow
 - [x] adjust domain organization file to allow referencing a specific element or family (perhaps do the domain
       summary on each family and combine the results)
 - [ ] adding to the above, a final HTML file with family-level identity and domain organization would be useful

 - Domain matches 
   - [ ] adjust duplicate domain filtering to consider strand and range of matches
   - [x] fix reporting of overlapping domain matches by LTRdigest? (issue reported: https://github.com/genometools/genometools/issues/706)
   - [x] add e-value threshold option and domain filtering method 

## Command `tephra findhelitrons`
 - [x] Find helitrons in reference sequences with HelitronScanner
 - [x] Generate GFF3 of full-length helitrons
 - [ ] Annotate coding domains in helitrons and include domains in GFF 
 - [x] Adjust header for full length elements to match output of other commands
 - [x] Remove strand from FASTA header for consistency with other commands

## Command `tephra findtrims`
 - [x] Find all non-overlapping TRIMs under strict and relaxed conditions
 - [x] Filter elements by quality score, retaining the best elements
 - [x] Generate combined GFF3 of high-quality TRIMs
 - [x] Create a feature type called 'TRIM_retrotransposon' to distinguish these elements from other LTR-RTs
 - [x] create developer tests to operate on a larger data set to positively identify elements rather than just
       operation of the command

## Command `tephra findnonltrs`
 - [ ] break chromosomes to reduce memory usage in hmmsearch (only applies to HMMERv3)
 - [x] check HMMERv22 var and program version
 - [x] remove backticks and shell exec of hmmer
 - [x] remove nasty regex parsing in favor or bioperl reading of report
 - [x] use list form of system to not fork
 - [x] run domain searches in parallel
 - [ ] use multiple CPUs (make option) for domain searches
 - [x] write GFF of results
 - [x] add verbose option so as to not print progress when there are 5k scaffolds
 - [x] write combined file of all elements
 - [x] take a multifasta as input and create directories for input/output to methods
 - [x] use complete elements to find truncated nonLTRs after masking (do this with complete file at the end
       on masked genome to get fragments for all types)
 - [x] use domain/blast based method for classifying elements into families
 - [ ] investigate issues related to why most elements reported on negative strand and contain
       many gaps
 - [ ] output protein domain sequences for phylogenetic analyses
 - [ ] refactor methods to use shared indexing and domain mapping methods
 - [ ] switch to using HMMERv3 models/programs from HMMERv2

## Command `tephra ltrage`
 - [x] Calculate age for each LTR-RT
 - [x] Take substitution rate as an option
 - [x] check if input directory exists
 - [ ] write age to GFF file
 - [x] Clean up results if requested

## Command `tephra maskref`
 - [x] Generate masked reference from custom repeat library 
 - [x] Add outfile option instead of creating filename
 - [x] Make some kind of statistical report about masking percentage. It would be helpful to format
       the output like RepeatMasker to give a global view of what was masked.
 - [x] Clean up the intermediate folders for each chromosome when masking the genome
 - [x] Create overlapping windows for masking subsets to solve the issue of reduced representation when
       generating smaller chunks

## Command `tephra illrecomb`

 - [x] Add correct sequence IDs to report
 - [ ] Investigate the apparent disagreement between the query/subject string and homology strings
 - [ ] Summarize the stats in a more intuitive way so it is clear what the gap summaries mean
 - [ ] Calculate stats from complete repeat database instead of just with LTRs
 - [ ] Do not write all families to disk before processing; do the analysis iteratively as we read the 
       repeat database

## Command `tephra tirage`

 - [x] Update menu for all available options.
 - [x] Add 3-letter code to age file IDs
 - [x] Clean up results if requested
 - [x] Add method to select the top families instead of --all (requires generating families first)

## Command `tephra all`

 - [ ] Allow the user to pass a genome and repeat database, along with a species name instead of configuration file.
 - [x] Generate summary statistics for TE types (domain content, length distribution, diversity, etc.) See
       (sesbio/transposon_annotation/count_families.pl) for starters.
 - [ ] Generate HTML output for all command. Will need to store JSON data for graphs and tables.
 - [x] Add tirage options to configuration file.
 - [x] Remove FASTA/GFF3 files of unclassified elements once the classification process is complete. 
 - [x] Consider removing all FASTA/GFF3 files except the final annotated products. Could add a 'splitgff3' command
       to produce separate FASTA/GFF3 files from a single GFF3 if going back to files split by TE type is 
       of interest.
 - [ ] Add method to filter LTRs/TIRs that appear to be duplicated genes. This method may fit better in the individual TE
       finding programs since the 'all' command is not the only use case of Tephra.
 - [x] Remove duplicate header in family-level domain organization file
 - [x] Fix Parent IDs getting mixed up when combining LTRs and TRIMs
 - [ ] Add final statistic showing full-length:solo-LTR:truncated ratios
 - [ ] Investigate vertical alignment of stats in log. This appears in Docker image in v0.12.1

## Command `tephra reannotate`

 - [ ] Add tests!
 - [ ] Log input FASTA and database used for transferring annotations

*** 

## Meta
 - [x] logging results/progress (need to log progress and errors to the correct location)
 - [x] add debug options for seeing commands (done for LTR search)
 - [ ] documentation of algorithms, in addition to usage
 - [x] reduce LTRs/TRIMs....perhaps when combining all GFFs
 - [ ] save tnp matching ltr-rts and search for cacta tes..or just add as putative classII
 - [ ] add kmer mapping command (see tallymer2gff.pl)
 - [x] create config role for setting paths
 - [x] change config module to be an Install namespace
 - [x] add subcommand to merge all GFFs (can be done with `gt gff3 sort`, though we want to be careful
       not to bake in too many subcommands for things that are easily done at the command line already,
       as this will make the package harder to use and maintain).
 - [x] handle compressed input/output (added for 'all' command in v0.12.3)
 - [X] add fasta-handling classes from Transposome, which are faster than BioPerl (Won't do: Added kseq.h methods from HTSlib)
 - [ ] add verbose option for quickly debugging the installation of dependencies
 - [x] add command to get TIR ages
 - [x] investigate why tests fail with Perl version 5.12 or lower (Bio::DB::HTS needs 5.14.2, so that's why)
 - [x] add subcommand to run/log all methods as a pipeline
 - [x] document the configuration file format and usage (on Github wiki, for now)
 - [x] add 'findfragments' subcommand to be run after final masking prior to complete GFF generation
 - [x] add classification method for TRIMs
 - [ ] move 'classify[ltr|tir]' commands to 'find[ltr|tir]' commands to simplify the process similar to the methods
       for the commands for helitrons and tirs
 - [ ] modify header to include element number in family. The element number should be listed numerically according 
       to chromosome position? (Wicker et al., 2007)
 - [x] add tryrosine recombinases, endonucleases, Helitron_like_N models from Pfam to HMM db
 - [ ] add 'solotir' command for discovering solo-TIRs
 - [x] add method to install MUSCLE along with other deps (added in v0.12.1)
 - [ ] check to see if we are calculating examplars for all TE types
 - [x] in DEV test mode, use A. thaliana for all tests

## Docker image
 - [ ] reduce EMBOSS install to only required programs
 - [ ] do not install BerkeleyDB and DB_FILE (Perl) since they are only recommended now, not required, by BioPerl since
       v1.7x
