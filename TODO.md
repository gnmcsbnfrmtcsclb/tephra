# TEPHRA TODO

This file is for logging feature requests and bugs during development. Hopefully, having one list will make it easier to keep track of proposed changes. It would be nice to rank the lists in order to prioritize tasks. It should be noted this list is for development purposes and it may go away once a stable release is made.

## Command `tephra classifyltrs`
 - [x] Classify 'best' LTR-RT elements into superfamilies based on domain content and organization
 - [x] Classify elements into families based on cluster organization; Generate FASTA for each family
 - [x] Create singletons file of ungrouped LTR-RT sequences
 - [x] Create FASTA files of exemplars for each LTR-RT family
 - [x] clean up logs and intermediate files from vmatch (dbluster-*)
 - [x] combine domain organization from both strands (if the same)?
 - [ ] add family classifications to GFF Name attribute and update with age
 - [ ] incorporate legacy annotations from input GFF/reference

## Command `tephra findtirs`
 - [x] Find all non-overlapping TIR elements passing thresholds
 - [x] Generate combined GFF3 of high-quality TIRs
 - [ ] Check for index (if given)

## Command `tephra sololtr`
 - [x] Create HMM of LTRs for each LTR-RT
 - [x] Search masked ref with LTR HMM
 - [x] Create GFF with SO terms of solo-LTRs
 - [ ] parallelize hmmsearch to speed things up. likely this is faster than multiple cpus for one model at time

## Command `tephra classifytirs`
 - [x] Classify 'best' TIR elements into superfamilies based on domain content, TSD, and/or motif
 - [x] Group TIR elements into families based on TIR similarity 
 - [ ] in tests, skip if empty output (none found). This is not a good test honestly, need a new reference
 - [ ] write fasta of each superfamily, and combined library

## Command `tephra findltrs` 
 - [x] Find all non-overlapping LTR-RTs under strict and relaxed conditions
 - [x] Filter elements by quality score, retaining the best elements
 - [x] Generate combined GFF3 of high-quality LTR-RTs
 - [ ] Check for index (if given)
 - [ ] change header format to be ">id_source_range"
 - [ ] adjust filtering command to not increment if element has been deleted (inflated filtering stats)
 - [ ] reporting of superfamilies after ltr search?.. better to do that at classification stage
 - [ ] add options for LTR size parameters

## Command `tephra findhelitrons`
 - [x] Find helitrons in reference sequences with HelitronScanner
 - [x] Generate GFF3 of full-length helitrons
 - [ ] Annotate coding domains in helitrons and include domains in GFF 

## Command `tephra findtrims`
 - [x] Find all non-overlapping TRIMs under strict and relaxed conditions
 - [x] Filter elements by quality score, retaining the best elements
 - [x] Generate combined GFF3 of high-quality TRIMs

## Command `tephra findnonltrs`
 - [ ] break chromosomes to reduce memory usage in hmmsearch (only applies to HMMERv3)
 - [x] check HMMER2 var and program version
 - [x] remove backticks and shell exec of hmmer
 - [x] remove nasty regex parsing in favor or bioperl reading of report
 - [x] use list form of system to not fork
 - [ ] run domain searches in parallel
 - [ ] use multiple CPUs (make option) for domain searches
 - [x] write GFF of results
 - [ ] add verbose option so as to not print progress when there are 5k scaffolds
 - [x] write combined file of all elements

## Command `tephra ltrage`
 - [x] Calculate age for each LTR-RT
 - [ ] Take substitution rate as an option

## Command `tephra maskref`
 - [x] Generate masked reference from custom repeat library 
 - [x] Add outfile option instead of creating filename

*** 

## Meta
 - [ ] logging results/progress
 - [ ] documentation
 - [ ] reduce LTRs/TRIMs....perhaps when combining all GFFs
 - [ ] save tnp matching ltr-rts and search for cacta tes..or just add as putative classII
 - [ ] add kmer mapping command (see tallymer2gff.pl)
 - [ ] create config role for setting paths
 - [ ] change config module to be an Install namespace
 - [ ] add subcommand to merge all GFFs