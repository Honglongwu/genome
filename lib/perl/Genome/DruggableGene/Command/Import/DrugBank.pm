package Genome::DruggableGene::Command::Import::DrugBank;

use strict;
use warnings;

use Genome;
use Term::ANSIColor qw(:constants);
use XML::Simple;

binmode(STDOUT, ":utf8");

my $high = 750000;
UR::Context->object_cache_size_highwater($high);

class Genome::DruggableGene::Command::Import::DrugBank {
    is => 'Genome::DruggableGene::Command::Import::Base',
    has => [
        infile => {
            is => 'Path',
            is_input => 1,
            doc => 'PATH.  XML data file downloaded from http://www.drugbank.ca/system/downloads/current/drugbank.xml.zip',
        },
        tmp_dir => {
            is => 'Path',
            default => '/tmp/',
            doc => 'Directory where temp files will be created',
        },
        verbose => {
            is => 'Boolean',
            is_input => 1,
            is_optional => 1,
            default => 0,
            doc => 'Print more output while running',
        },
        skip_pubchem => {
            is => 'Boolean',
            is_input => 1,
            is_optional => 1,
            default => 0,
            doc => 'Skip _destroy_and_rebuild_pubchem_and_drug_groups step',
        },
        drugs_outfile => {
            is => 'Path',
            is_input => 1,
            default => '/gscmnt/sata132/techd/mgriffit/DruggableGenes/TSV/DrugBank_WashU_DRUGS.tsv',
            doc => 'PATH.  Path to .tsv file for drugs',
        },
        genes_outfile => {
            is => 'Path',
            is_input => 1,
            default => '/gscmnt/sata132/techd/mgriffit/DruggableGenes/TSV/DrugBank_WashU_TARGETS.tsv',
            doc => 'PATH.  Path to .tsv file for genes (targets)',
        },
        interactions_outfile => {
            is => 'Path',
            is_input => 1,
            default => '/gscmnt/sata132/techd/mgriffit/DruggableGenes/TSV/DrugBank_WashU_INTERACTIONS.tsv',
            doc => 'PATH.  Path to .tsv file for drug gene interactions',
        },
        citation_base_url => {
            default => 'http://drugbank.ca/',
        },
        citation_site_url => {
            default => 'http://www.drugbank.ca/',
        },
        citation_text => {
            default => "DrugBank 3.0: a comprehensive resource for 'omics' research on drugs. Knox C, Law V, ..., Eisner R, Guo AC, Wishart DS. Nucleic Acids Res. 2011 Jan;39(Database issue)1035-41. PMID: 21059682.",
        },
    ],
    doc => 'Parse an XML database file from DrugBank',
};

sub _doc_copyright_years {
    (2011);
}

sub _doc_license {
    my $self = shift;
    my (@y) = $self->_doc_copyright_years;  
    return <<EOS
Copyright (C) $y[0] Washington University in St. Louis.

It is released under the Lesser GNU Public License (LGPL) version 3.  See the 
associated LICENSE file in this distribution.
EOS
}

sub _doc_authors {
    return <<EOS
 Malachi Griffith, Ph.D.
 Jim Weible
EOS
}

=cut
sub _doc_credits {
    return ('','None at this time.');
}
=cut

sub _doc_see_also {
    return <<EOS
B<genome>(1)
EOS
}

sub _doc_manual_body {
    my $help = shift->help_detail;
    $help =~ s/\n+$/\n/g;
    return $help;
}

sub help_synopsis {
    return <<HELP
genome druggable-gene import drug-bank --infile=/gscmnt/sata132/techd/mgriffit/DruggableGenes/KnownDruggable/DrugBank/drugbank.xml --verbose --version="3.0"
HELP
}

sub help_detail {
    my $summary = <<HELP
Parse an XML database file from DrugBank
Get drug, interaction and gene info for each drug-gene interaction in the database
Get gene names and uniprot IDs from Entrez gene
Add official 'EntrezGene' name to each gene record
HELP
}

my %UniProtMapping;

sub execute {
    my $self = shift;
    %UniProtMapping=%{$self->_get_uniprot_entrez_mapping()}; #Load UniProt to Entrez mapping information from file (For Uniprot -> Entrez mapping)
    $self->input_to_tsv();
    $self->import_tsv();
    unless ($self->skip_pubchem){
        $self->_destroy_and_rebuild_pubchem_and_drug_groups();
    }
    return 1;
}

sub import_tsv {
    my $self = shift;
    my $drugs_outfile = $self->drugs_outfile;
    my $targets_outfile = $self->genes_outfile;
    my $interactions_outfile = $self->interactions_outfile;
    $self->preload_objects;
    my $citation = $self->_create_citation('DrugBank', $self->version, $self->citation_base_url, $self->citation_site_url, $self->citation_text, 'DrugBank - Open Data Drug & Drug Target Database');
    my @interactions = $self->import_interactions($interactions_outfile, $citation);
    return 1;
}

sub _import_drug {
    my $self = shift;
    my $interaction = shift;
    my $citation = shift;
    my $drug_name = $self->_create_drug_name_report($interaction->{drug_id}, $citation, 'DrugBank Drug Identifier', '');
    my $drug_name_alt = $self->_create_drug_alternate_name_report($drug_name, $interaction->{drug_id}, 'DrugBank Drug Id', '');
    my $primary_name = $self->_create_drug_alternate_name_report($drug_name, $interaction->{drug_name}, 'Primary Drug Name', '');

    my @drug_synonyms = split(', ', $interaction->{drug_synonyms});
    for my $drug_synonym (@drug_synonyms){
        next if $drug_synonym eq 'N/A';
        my $drug_name_association = $self->_create_drug_alternate_name_report($drug_name, $drug_synonym, 'Drug Synonym', '');
    }

    my @drug_brands = split(', ', $interaction->{drug_brands});
    for my $drug_brand (@drug_brands){
        next if $drug_brand eq 'N/A';
        my ($brand, $manufacturer) = split(/ \(/, $drug_brand); 
        if ($manufacturer){
            $manufacturer =~ s/\)// ;
        } else {
            $manufacturer = 'Drug Brand';
        }
        my $drug_name_association = $self->_create_drug_alternate_name_report($drug_name, $drug_brand, $manufacturer, '');
    }

    unless($interaction->{drug_type} eq 'N/A'){
        my $drug_name_category_association = $self->_create_drug_category_report($drug_name, 'Drug Type', $interaction->{drug_type}, '');
    }

    unless($interaction->{drug_cas_number} eq 'N/A'){
        my $drug_name_cas_number = $self->_create_drug_alternate_name_report($drug_name, $interaction->{drug_cas_number}, 'CAS Number', '');
    }

    my @drug_categories = split(', ', $interaction->{drug_categories});
    for my $drug_category (@drug_categories){
        next if $drug_category eq 'N/A';
        my $category_association = $self->_create_drug_category_report($drug_name, 'Drug Category', $drug_category, '');
    }

    my @drug_groups = split(', ', $interaction->{drug_groups});
    for my $drug_group (@drug_groups){
        next if $drug_group eq 'N/A';
        my $group_association = $self->_create_drug_category_report($drug_name, 'Drug Group', $drug_group, '');
    }

    return $drug_name;
}

sub _import_gene {
    my $self = shift;
    my $interaction = shift;
    my $citation = shift;
    my $gene_partner_id = $interaction->{partner_id};
    my $gene_symbol = $interaction->{gene_symbol};
    my $uniprot_id = $interaction->{uniprot_id};
    my $entrez_id = $interaction->{entrez_id};
    my $ensembl_id = $interaction->{ensembl_id};
    #If a gene has no gene_symbol or uniprot_id, it isn't a "real" gene. Do not make a gene for this non gene
    if ($uniprot_id eq 'N/A' and $gene_symbol eq 'N/A'){
      return;
    }
    #If a uniprot ID is present, but doesn't map to a human entrez id (all that is attempted) then it is probably not human, don't import
    if ($uniprot_id and ($uniprot_id ne 'N/A')){
        unless ($UniProtMapping{$uniprot_id}){
          return;
        }     
    }
    my $gene_name = $self->_create_gene_name_report($gene_partner_id, $citation, 'Drugbank Partner Id', '');
    #my $gene_name_alt = $self->_create_gene_alternate_name_report($gene_name, $gene_partner_id, 'Drugbank Gene Id', '');
    unless ($gene_symbol eq 'N/A'){
        my $gene_symbol_gene_name_association = $self->_create_gene_alternate_name_report($gene_name, $gene_symbol, 'Drugbank Gene Name', '');
    }
    unless ($uniprot_id eq 'N/A'){
        my $uniprot_gene_name_association=$self->_create_gene_alternate_name_report($gene_name, $uniprot_id, 'Uniprot Accession', '');
    }
    unless ($entrez_id eq 'N/A'){
        my $entrez_id_association=$self->_create_gene_alternate_name_report($gene_name, $entrez_id, 'Entrez Gene Id', '');
    }
    unless ($ensembl_id eq 'N/A'){
        my $ensembl_id_association=$self->_create_gene_alternate_name_report($gene_name, $ensembl_id, 'Ensembl Gene Id', '');
    }
    return $gene_name;
}

sub import_interactions {
    my $self = shift;
    my $interaction_outfile = shift;
    my $citation = shift;
    my @interactions;
    my @headers = qw/ interaction_count drug_id drug_name drug_synonyms drug_cas_number drug_brands drug_type drug_groups drug_categories partner_id known_action target_actions gene_symbol uniprot_id entrez_id ensembl_id /;
    my $parser = Genome::Utility::IO::SeparatedValueReader->create(
        input => $interaction_outfile,
        headers => \@headers,
        separator => "\t",
        is_regex=> 1,
    );

    $parser->next; #eat the headers
    while(my $interaction = $parser->next){
        my $gene_name = $self->_import_gene($interaction, $citation);
        next unless $gene_name; #if no gene was created, there is no gene for this interaction.  Skip this drug and interaction
        my $drug_name = $self->_import_drug($interaction, $citation);
        my $drug_gene_interaction = $self->_create_interaction_report($citation, $drug_name, $gene_name, '');
        push @interactions, $drug_gene_interaction;
        my $is_known_action = $self->_create_interaction_report_attribute($drug_gene_interaction, 'Is Known Action', $interaction->{'known_action'});
        my @interaction_types = split(', ', $interaction->{target_actions});
        for my $interaction_type (@interaction_types){
            my $type_attribute = $self->_create_interaction_report_attribute($drug_gene_interaction, 'Interaction Type', $interaction_type);
        }
    }

    return @interactions;
}

sub preload_objects {
    my $self = shift;
    my $source_db_name = 'DrugBank';
    my $source_db_version = $self->version;
    my $verbose = $self->verbose;
    if ($verbose){
        print BLUE, "\nAttempting to preload objects\n", RESET;
    }
    #Let's preload anything for this database name and version so that we can avoid death by 1000 queries
    my @gene_names = Genome::DruggableGene::GeneNameReport->get(source_db_name => $source_db_name, source_db_version => $source_db_version);
    for my $gene_name (@gene_names){
        $gene_name->gene_alt_names;
        $gene_name->gene_categories;
    }
    my @drug_names = Genome::DruggableGene::DrugNameReport->get(source_db_name => $source_db_name, source_db_version => $source_db_version);
    for my $drug_name (@drug_names){
        $drug_name->drug_alt_names;
        $drug_name->drug_categories;
    }
    my @gene_ids = map($_->id, @gene_names);
    my @interactions = Genome::DruggableGene::DrugGeneInteractionReport->get(gene_id => \@gene_ids);
    for my $interaction (@interactions){
        $interaction->interaction_attributes;
    }
    return 1;
}

sub help_usage_complete_text {
    my $self = shift;
    my $usage = $self->SUPER::help_usage_complete_text(@_);
    return GREEN . $usage . RESET;
}

sub input_to_tsv {
    my $self = shift;
    my $infile = $self->infile;
    my $verbose = $self->verbose;

    #We're going to import everything as is deal with Entrez gene names upon retrevial

    #Instantiate an XML simple object
    my $xs1 = XML::Simple->new();

    #Create data object for the entire XML file, allowing mixed array/hash structure for the same field depending of whether is only one element or more than one.
    #Also actually specify the primary IDs you would like the resultng data structures to be keyed on ('drugbank-id' for drug records, 'id' for gene partners)
    my $xml = $xs1->XMLin($infile, KeyAttr => ['drugbank-id', 'id'] );

    #Get the 'drug' tree
    my $info_source = "DrugBank";
    my $drugs = $xml->{'drug'};

    #Get the partners tree
    #Unfortunately, the primary key of this tree is the gene name but drug intereactions seem to be linked by 'partner id'
    #This means that we can not directly look up partner records for each drug.  We must traverse the partner hash for each drug (slow) or create a new data structure that is keyed in partner ID
    my $partners = $xml->{'partners'};

    #Build a new simpler partners object for convenience - since it is keyed on partner ID we could access directly as well...
    my $partners_lite = $self->organizePartners('-partner_ref'=>$partners);

    #Count distinct drug-gene interactions
    my $ic = 0;

    #Create three output files: Drugs, Targets, Interactions
    my $drugs_outfile = $self->drugs_outfile;
    my $targets_outfile = $self->genes_outfile;
    my $interactions_outfile = $self->interactions_outfile;
    open(DRUGS, ">$drugs_outfile") || die "\n\nCould not open outfile: $drugs_outfile\n\n";
    binmode(DRUGS, ":utf8");
    open(TARGETS, ">$targets_outfile") || die "\n\nCould not open outfile: $targets_outfile\n\n";
    binmode(TARGETS, ":utf8");
    open(INTERACTIONS, ">$interactions_outfile") || die "\n\nCould not open outfile: $interactions_outfile\n\n";
    binmode(INTERACTIONS, ":utf8");

    #Print out a header line foreach output file
    my $interactions_header = "interaction_count\tdrug_id\tdrug_name\tdrug_synonyms\tdrug_cas_number\tdrug_brands\tdrug_type\tdrug_groups\tdrug_categories\tpartner_id\tknown_action?\ttarget_actions\tgene_symbol\tuniprot_id\tentrez_id\tensembl_id";
    print INTERACTIONS "$interactions_header\n";

    my $drugs_header = "drug_id\tdrug_name\tdrug_synonyms\tdrug_cas_number\tdrug_brands\tdrug_type\tdrug_groups\tdrug_categories\ttarget_count";
    print DRUGS "$drugs_header\n";

    my $targets_header = "partner_id\tgene_symbol\tuniprot_id\tentrez_id\tensembl_id";
    print TARGETS "$targets_header\n";

    foreach my $drug_id (sort {$a cmp $b} keys %{$drugs}){
        my $drug_name = $drugs->{$drug_id}->{'name'};
        my $drug_type = $drugs->{$drug_id}->{'type'};
        if ($verbose){
            print BLUE, "\n\n$drug_id\t$drug_type\t$drug_name", RESET;
        }

        #Get the cas_number
        my $drug_cas_number = 'N/A';
        unless(ref($drugs->{$drug_id}->{'cas-number'})){
            $drug_cas_number = $drugs->{$drug_id}->{'cas-number'};
        }

        #Get the drug groups
        my $group_list = $drugs->{$drug_id}->{'groups'};
        my @groups = @{$self->parseTree('-ref'=>$group_list, '-value_name'=>'group')};
        if ($verbose){
            print BLUE, "\nGroups: @groups", RESET;
        }
        my $drug_groups_string = join(",", @groups);

        #Get the drug synonyms
        my $synonym_list = $drugs->{$drug_id}->{'synonyms'};
        my @synonyms = @{$self->parseTree('-ref'=>$synonym_list, '-value_name'=>'synonym')};
        if ($verbose){
            print BLUE, "\nSynonyms: @synonyms", RESET;
        }
        my $drug_synonyms_string = join(",", @synonyms);

        #Get the drug brands
        my $brand_list = $drugs->{$drug_id}->{'brands'};
        my @brands = @{$self->parseTree('-ref'=>$brand_list, '-value_name'=>'brand')};
        if ($verbose){
            print BLUE, "\nBrands: @brands", RESET;
        }
        my $drug_brands_string = join(",", @brands);

        #Get the drug categories
        my $category_list = $drugs->{$drug_id}->{'categories'};
        my @categories = @{$self->parseTree('-ref'=>$category_list, '-value_name'=>'category')};
        if ($verbose){
            print BLUE, "\nCategories: @categories", RESET;
        }
        my $drug_categories_string = join(",", @categories);

        #Get the targets.  i.e. the gene parter ids for this drug
        my $targets = $drugs->{$drug_id}->{'targets'};
        my $target_list = $targets->{'target'};
        my @target_partners = @{$self->parseTree('-ref'=>$target_list, '-value_name'=>'partner')};
        my $t_count = scalar(@target_partners);

        #Get the known action status (yes|unknown|no?) for this drug
        my @target_known_actions = @{$self->parseTree('-ref'=>$target_list, '-value_name'=>'known-action')};

        #Get the actions associated with each drug->gene target interaction.  Note that there can be more than one action for each interaction - only defined if the action status was "yes"
        my @action_lists =  @{$self->parseTree('-ref'=>$target_list, '-value_name'=>'actions')};
        my @target_actions_joined;
        foreach my $action_list (@action_lists){
            my @actions =  @{$self->parseTree('-ref'=>$action_list, '-value_name'=>'action')};
            my $action_string = join(",", @actions);
            push(@target_actions_joined, $action_string);
        }
        if ($verbose){
            print "\n\tTarget Partners: @target_partners";
            print "\n\tTarget Known Actions: @target_known_actions";
            print "\n\tTarget Actions: @target_actions_joined";
        }

        #Strip <tabs> from string variables
        $drug_name =~ s/\t/ /g;
        $drug_cas_number =~ s/\t/ /g;
        $drug_synonyms_string =~ s/\t/ /g;
        $drug_brands_string =~ s/\t/ /g;
        $drug_type =~ s/\t/ /g;
        $drug_groups_string =~ s/\t/ /g;
        $drug_categories_string =~ s/\t/ /g;

        #Print out each drug
        my $drugs_line = "$drug_id\t$drug_name\t$drug_synonyms_string\t$drug_cas_number\t$drug_brands_string\t$drug_type\t$drug_groups_string\t$drug_categories_string\t$t_count";
        print DRUGS "$drugs_line\n";

        #Print out each drug-gene interaction...
        for (my $i = 0; $i < $t_count; $i++){
            my $target_pid = $target_partners[$i];
            my $target_known_action = $target_known_actions[$i];
            my $target_actions = $target_actions_joined[$i];

            unless ($partners_lite->{$target_pid}){
                print RED, "\n\nTarget PID: $target_pid is not defined in the partners hash\n\n", RESET;
                exit();
            }
            my $gene_symbol = $partners_lite->{$target_pid}->{gene_symbol};
            my $uniprotkb = $partners_lite->{$target_pid}->{uniprotkb};

            #Retrieve Entrez/Ensembl IDs for interaction protein (if available)
            my $entrez_id = "N/A";
            my $ensembl_id = "N/A";
            if ($UniProtMapping{$uniprotkb}){
              $entrez_id = $UniProtMapping{$uniprotkb}{entrez_id};
              $ensembl_id = $UniProtMapping{$uniprotkb}{ensembl_id};
            }

            #Strip <tabs> from string variables
            $target_known_action =~ s/\t/ /g;
            $target_actions =~ s/\t/ /g;

            $ic++;
            my $interactions_line = "$ic\t$drug_id\t$drug_name\t$drug_synonyms_string\t$drug_cas_number\t$drug_brands_string\t$drug_type\t$drug_groups_string\t$drug_categories_string\t$target_pid\t$target_known_action\t$target_actions\t$gene_symbol\t$uniprotkb\t$entrez_id\t$ensembl_id";
            print INTERACTIONS "$interactions_line\n";
        }
    }

    foreach my $pid (sort {$a <=> $b} keys %{$partners_lite}){
        my $gene_symbol = $partners_lite->{$pid}->{gene_symbol};
        my $uniprot_id = $partners_lite->{$pid}->{uniprotkb};
        #Retrieve Entrez/Ensembl IDs for interaction protein (if available)
        my $entrez_id = "N/A";
        my $ensembl_id = "N/A";
        if ($UniProtMapping{$uniprot_id}){
          $entrez_id = $UniProtMapping{$uniprot_id}{entrez_id};
          $ensembl_id = $UniProtMapping{$uniprot_id}{ensembl_id};
        }
        my $targets_line = "$pid\t$gene_symbol\t$uniprot_id\t$entrez_id\t$ensembl_id";
        print TARGETS "$targets_line\n";
    }

    close(DRUGS);
    close(TARGETS);
    close(INTERACTIONS);

    print "\n\n";
    return 1;
}

##########################################################################################################################################
#Utility function for grabbing values from hash/array structures                                                                          
##########################################################################################################################################
sub parseTree{
    my $self = shift;
    my %args = @_;
    my $ref = $args{'-ref'};
    my $value_name = $args{'-value_name'};

    #If there was only one record for this data type in the XML, a reference to a key-value HASH will be returned, otherwise a reference to an ARRAY will be returned
    #Figure out which is the case ...
    my $ref_test = ref($ref);
    my @values;
    if ($ref_test eq "HASH"){
        my $value = $ref->{$value_name};

        #If you still have an array reference... dereference, join into a string, and push onto an array
        if (ref($value) eq "ARRAY"){
        #print YELLOW, "\nDebug: $value", RESET;
            my @tmp = @{$value};
            $value = join(", ", @tmp);
        }

        if (defined($value)){
            push(@values, $value);
        }else{
            push(@values, "N/A");
        }
    }else{
        foreach my $x (@{$ref}){
            my $value = $x->{$value_name};
            if (defined($value)){
                push(@values, $value);
            }else{
                push(@values, "N/A");
            }
        }
    }
    return(\@values);
}


###################################################################################################################################
#Build a new partners object keyed on partner ID                                                                                  #
###################################################################################################################################
sub organizePartners{
    my $self = shift;
    my $verbose = $self->verbose;
    my %args = @_;
    my $p_ref = $args{'-partner_ref'};
    my %p_lite;

    if ($verbose){
        print BLUE, "\n\nBuilding new 'partner lite' object\n\n", RESET;
    }
    my $p = $p_ref->{'partner'};

    foreach my $pid (keys %{$p}){

        #Get the gene symbol
        my $gene_symbol;
        my $gene_symbol_r = $p->{$pid}->{'gene-name'};
        if (ref($gene_symbol_r) eq "HASH"){
            $gene_symbol = %{$gene_symbol_r};
        }else{
            $gene_symbol = $gene_symbol_r;
        }
        unless ($gene_symbol){
            $gene_symbol = "N/A";
        }

        #Get the gene name
        my $gene_name;
        my $gene_name_r = $p->{$pid}->{'name'};
        if (ref($gene_name_r) eq "HASH"){
            $gene_name = %{$gene_name_r};
        }else{
            $gene_name = $gene_name_r;
        }
        unless ($gene_name){
            $gene_name = "N/A";
        }

        if ($verbose){
            print YELLOW, "\n\t$pid\t$gene_symbol\t$gene_name", RESET;
        }

        #Get the external identifiers - for now, just store the UniProt ID
        my %external_ids;
        my $ext_id_ref = $p->{$pid}->{'external-identifiers'};
        my $ext_id_list = $ext_id_ref->{'external-identifier'};
        if (ref($ext_id_list) eq "ARRAY"){
            foreach my $eid (@{$ext_id_list}){
                my $resource = $eid->{'resource'};
                my $identifier = $eid->{'identifier'};
                $external_ids{$resource} = $identifier;
                if ($verbose){
                    print YELLOW, "\n\t\t$resource\t$identifier", RESET;
                }
            }
        }else{
            if ($ext_id_list->{'resource'}){
                my $resource = $ext_id_list->{'resource'};
                my $identifier = $ext_id_list->{'identifier'};
                if ($verbose){
                    print YELLOW, "\n\t\t$resource\t$identifier", RESET;
                }
                $external_ids{$resource} = $identifier;
            }else{
                if ($verbose){
                    print RED, "\n\t\tFound no external IDs at all", RESET;
                }
            }
        }
        my $uniprotkb = "N/A";
        if ($external_ids{'UniProtKB'}){
            $uniprotkb = $external_ids{'UniProtKB'};
        }

        #Store the info gathered thus far in the simplifed data structure keyed on partner ID
        #Remove <tabs> just in case
        $gene_symbol =~ s/\t/ /g;
        $gene_name =~ s/\t/ /g;
        $uniprotkb =~ s/\t/ /g;
        $p_lite{$pid}{gene_symbol} = $gene_symbol;
        $p_lite{$pid}{gene_name} = $gene_name;
        $p_lite{$pid}{uniprotkb} = $uniprotkb;
    }

#print Dumper %p_lite;
#foreach my $pid (sort {$a <=> $b} keys %p_lite){
#  print CYAN, "\n$pid\t$p_lite{$pid}{gene_name}\t$p_lite{$pid}{drug_name}\t$p_lite{$pid}{uniprotkb}", RESET;
#}

    return(\%p_lite);
}

sub download_file {
    my $self = shift;
    my %args = @_;
    my $url = $args{'-mapping_file_url'};
    my $targetfilename = $args{'-mapping_file_name'};
    my $tempdir = $self->tmp_dir;
    my $targetfilepath="$tempdir"."$targetfilename";
    my $wget_cmd = "wget $url -O $targetfilepath";
    my $retval = Genome::Sys->shellcmd(cmd=>$wget_cmd);
    unless ($retval == 1){
      self->error_message('Failed to wget the specified URL');
      return;
    }
    #unzip if necessary
    if ($targetfilepath=~/\.gz$/){
      my $gunzip_cmd = "gunzip -f $targetfilepath";
      my $retval2 = Genome::Sys->shellcmd(cmd=>$gunzip_cmd);
      unless ($retval2 == 1){
        self->error_message('Failed to gunzip the specified file');
        return;
      }
      $targetfilepath=~s/\.gz$//;
    }
    print "Downloaded $targetfilepath\n";
    return $targetfilepath;
}

1;
