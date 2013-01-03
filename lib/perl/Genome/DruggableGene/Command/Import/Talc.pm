package Genome::DruggableGene::Command::Import::Talc;

use strict;
use warnings;
use Genome;

binmode(STDOUT, ":utf8");

class Genome::DruggableGene::Command::Import::Talc {
  is => 'Genome::DruggableGene::Command::Import::Base',
  has => [
        infile => {
            is => 'Path',
            is_input => 1,
            doc => 'PATH.  Tab-delim text file provided by collaborators',
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
        interactions_outfile => {
            is => 'Path',
            is_input => 1,
            default => '/gscmnt/sata132/techd/mgriffit/DruggableGenes/TSV/TALC_WashU_INTERACTIONS.tsv',
            doc => 'PATH.  Path to .tsv file for drug gene interactions',
        },
        version => {
            is => 'Text',
            is_input => 1,
            doc => 'VERSION.  Version (date) of release of database from TALC group',
        },
        citation_base_url => {
            default => 'http://www.ncbi.nlm.nih.gov/gene?term=', #For genes, use Entrez ID, Drugs will have to be handled as special case.
        },
        citation_site_url => {
            default => 'http://www.ncbi.nlm.nih.gov/pubmed/22005529/',
        },
        citation_text => {
            default => 'Molecular targeted agents and biologic therapies for lung cancer.  Somaiah N, Simon GR.  J Thorac Oncol. 2011 Nov;6(11 Suppl 4):S1758-85.  PMID: 22005529',
        },
    ],
    doc => 'Parse a tab-delim file from collaborators for TALC database',
};

sub _doc_copyright_years {
    (2012);
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
 Obi Griffith, Ph.D.
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
genome druggable-gene import talc --infile=/gscmnt/sata132/techd/mgriffit/DruggableGenes/KnownDruggable/SantaMonicaLung/clean/SantaMonicaLungCancerDrugDatabase.tsv --version="16-Jul-2012" --verbose
HELP
}

sub help_detail {
    my $summary = <<HELP
Parse a tab-delimited database file from the TALC group (published annually)
Get drug, interaction and gene info for each drug-gene interaction in the database
Get gene names and uniprot IDs from Entrez gene
Add official 'EntrezGene' name to each gene record
HELP
}

sub execute {
    my $self = shift;
    $self->input_to_tsv();
    $self->import_tsv();
    unless ($self->skip_pubchem){
        $self->_destroy_and_rebuild_pubchem_and_drug_groups();
    }
    return 1;
}

sub import_tsv {
    my $self = shift;
    my $interactions_outfile = $self->interactions_outfile;
    $self->preload_objects;
    my @interactions = $self->import_interactions($interactions_outfile);
    return 1;
}

sub import_interactions {
    my $self = shift;
    my $interactions_outfile = shift;
    my $version = $self->version;
    my @interactions;
    my @headers = qw(interaction_id gene_target drug_name interaction_type drug_class drug_type drug_generic_name drug_trade_name drug_synonym entrez_id drug_cas_number drug_drugbank_id);
    my $parser = Genome::Utility::IO::SeparatedValueReader->create(
        input => $interactions_outfile,
        headers => \@headers,
        separator => "\t",
        is_regex => 1,
    );

    my $citation = $self->_create_citation('TALC', $version, $self->citation_base_url, $self->citation_site_url, $self->citation_text, 'Targeted Agents in Lung Cancer (Santa Monica Supplement, 2011)');

    $parser->next; #eat the headers
    while(my $interaction = $parser->next){
        my $drug_name = $self->_import_drug($interaction, $citation);
        my $gene_name = $self->_import_gene($interaction, $citation);
        my $drug_gene_interaction = $self->_create_interaction_report($citation, $drug_name, $gene_name, '');
        push @interactions, $drug_gene_interaction;
        if($interaction->{interaction_type} eq 'N/A'){
          my $type_attribute = $self->_create_interaction_report_attribute($drug_gene_interaction, 'Interaction Type', 'n/a');
        }else{
          my $type_attribute = $self->_create_interaction_report_attribute($drug_gene_interaction, 'Interaction Type', $interaction->{interaction_type});
        }
    }
    return @interactions;
}

sub _import_drug {
    my $self = shift;
    my $interaction = shift;
    my $citation = shift;
    my $drug_name = $self->_create_drug_name_report($interaction->{drug_name}, $citation, 'TALC', '');
    my $primary_drug_name = $self->_create_drug_alternate_name_report($drug_name, $interaction->{drug_name}, 'Primary Drug Name', '');
    my @drug_synonyms = split(",", $interaction->{drug_synonym});
    for my $drug_synonym (@drug_synonyms){
      next if $drug_synonym eq 'N/A';
      my $synonym_association = $self->_create_drug_alternate_name_report($drug_name, $drug_synonym, 'Drug Synonym', '');
    }

    unless($interaction->{drug_generic_name} eq 'N/A'){
        my $drug_generic_name = $self->_create_drug_alternate_name_report($drug_name, $interaction->{drug_generic_name}, 'Drug Generic Name', '');

    }

    my @drug_tradenames = split(",", $interaction->{drug_trade_name});
    for my $drug_tradename (@drug_tradenames){
      next if $drug_tradename eq 'N/A';
      my $tradename_association = $self->_create_drug_alternate_name_report($drug_name, $drug_tradename, 'Drug Trade Name', '');
    }

    unless($interaction->{drug_cas_number} eq 'N/A'){
        my $drug_name_cas_number = $self->_create_drug_alternate_name_report($drug_name, $interaction->{drug_cas_number}, 'CAS Number', '');
    }

    unless($interaction->{drug_drugbank_id} eq 'N/A'){
        my $drug_name_drugbank_id = $self->_create_drug_alternate_name_report($drug_name, $interaction->{drug_drugbank_id}, 'Drugbank Id', '');
    }

    unless($interaction->{drug_class} eq 'N/A'){
        my $drug_class = $self->_create_drug_category_report($drug_name, 'Drug Class', $interaction->{drug_class}, '');
    }

    unless($interaction->{drug_type} eq 'N/A'){
        my $drug_type = $self->_create_drug_category_report($drug_name, 'Drug Type', $interaction->{drug_type}, '');
    }
    return $drug_name;
}

sub _import_gene {
    my $self = shift;
    my $interaction = shift;
    my $citation = shift;
    my $gene_name = $self->_create_gene_name_report($interaction->{entrez_id}, $citation, 'Entrez Gene Id', '');
    my $gene_id_association = $self->_create_gene_alternate_name_report($gene_name, $interaction->{entrez_id}, 'Entrez Gene Id', '', 'upper');
    my $gene_name_association = $self->_create_gene_alternate_name_report($gene_name, $interaction->{gene_target}, 'Gene Symbol', '', 'upper');
    return $gene_name;
}

sub input_to_tsv {
    my $self = shift;
    my $infile = $self->infile;

    #Create interactions output file
    my $interactions_outfile = $self->interactions_outfile;
    my $interactions_fh = IO::File->new($interactions_outfile, 'w');
    my $interactions_header = join("\t", 'interaction_id', 'gene_target','drug_name', 'interaction_type', 'drug_class','drug_type','drug_generic_name','drug_trade_name','drug_synonym','entrez_id','drug_cas_number','drug_drugbank_id');
    $interactions_fh->print($interactions_header, "\n");

    #Get the data in order
    my $infile_path = $infile;

    my ($targets, $drugs) = $self->_parse_targets_file($infile_path);

    #Write data to the file
    for my $target_id (keys %{$targets}){
        #Target Interaction Id
        my $interaction_id =  $targets->{$target_id}{'interaction_id'};
        $interaction_id = 'N/A' unless $interaction_id;

        #Target Gene Name
        my $gene_target =  $targets->{$target_id}{'gene_target'};
        $gene_target = 'N/A' unless $gene_target;

        #Target Gene Entrez Id
        my $entrez_id =  $targets->{$target_id}{'entrez_id'};
        $entrez_id = 'N/A' unless $entrez_id;

        #Interaction Type 
        my $interaction_type = $targets->{$target_id}{'interaction_type'};
        $interaction_type = 'N/A' unless $interaction_type;

        #Drug name
        my $drug_name = $targets->{$target_id}{'drug_name'};
        $drug_name = 'N/A' unless $drug_name;

        #Drug class
        my $drug_class = $drugs->{$drug_name}{'drug_class'};
        $drug_class = 'N/A' unless $drug_class;

        #Drug type
        my $drug_type = $drugs->{$drug_name}{'drug_type'};
        $drug_type = 'N/A' unless $drug_type;

        #drug_generic_name
        my $drug_generic_name = $drugs->{$drug_name}{'drug_generic_name'};
        $drug_generic_name = 'N/A' unless $drug_generic_name;

        #drug_trade_name
        my $drug_trade_name = $drugs->{$drug_name}{'drug_trade_name'};
        $drug_trade_name = 'N/A' unless $drug_trade_name;

        #drug_synonym
        my $drug_synonyms = $drugs->{$drug_name}{'drug_synonym'};
        $drug_synonyms = 'N/A' unless $drug_synonyms;

        #drug_drugbank_id
        my $drug_drugbank_id = $drugs->{$drug_name}{'drug_drugbank_id'};
        $drug_drugbank_id = 'N/A' unless $drug_drugbank_id;

        #CAS Number
        my $drug_cas_number = $drugs->{$drug_name}{'drug_cas_number'};
        $drug_cas_number = 'N/A' unless $drug_cas_number;

        $interactions_fh->print(join("\t", $interaction_id, $gene_target, $drug_name, $interaction_type, $drug_class, $drug_type, $drug_generic_name, $drug_trade_name, $drug_synonyms, $entrez_id, $drug_cas_number, $drug_drugbank_id), "\n");
        
    }
    $interactions_fh->close;
    return 1;
}

sub preload_objects {
    my $self = shift;
    my $source_db_name = 'TALC';
    my $source_db_version = $self->version;

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

sub _parse_targets_file {
    my $self = shift;
    my $targets_path = shift;
    my $targets = {};
    my $drugs = {};
    my $fh = IO::File->new($targets_path, 'r');

    while(my $line = <$fh>){
        next unless $line;
        chomp $line;
        $line =~ s/\r//g;
        if($line =~ m/^SML\w+/){
            my ($interaction_id, $gene_target, $drug_name, $interaction_type, $drug_class, $drug_type, $drug_generic_name, $drug_trade_name, $drug_synonym, $entrez_id, $drug_cas_number, $drug_drugbank_id) = split("\t", $line);
        $targets->{$interaction_id}{'interaction_id'} = $interaction_id;
        $targets->{$interaction_id}{'gene_target'} = $gene_target;
        $targets->{$interaction_id}{'drug_name'} = $drug_name;
        $targets->{$interaction_id}{'interaction_type'} = $interaction_type;
        $targets->{$interaction_id}{'entrez_id'} = $entrez_id;

        #Note: This assumes that if a drug appears more than once, all drug annotations will be the same
        $drugs->{$drug_name}{'drug_class'} = $drug_class;
        $drugs->{$drug_name}{'drug_type'} = $drug_type;
        $drugs->{$drug_name}{'drug_generic_name'} = $drug_generic_name;
        $drugs->{$drug_name}{'drug_trade_name'} = $drug_trade_name;
        $drugs->{$drug_name}{'drug_synonym'} = $drug_synonym;
        $drugs->{$drug_name}{'drug_cas_number'} = $drug_cas_number;
        $drugs->{$drug_name}{'drug_drugbank_id'} = $drug_drugbank_id;
        }else{
            #skip this line
            next;
        }
    }
    $fh->close;
    return ($targets, $drugs);
}

1;

