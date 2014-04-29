package Genome::Annotation::Interpreter::VepInterpreter;

use strict;
use warnings;
use Genome;
use Genome::File::Vcf::VepConsequenceParser;

class Genome::Annotation::Interpreter::VepInterpreter {
    is => 'Genome::Annotation::Interpreter::Base',
};

sub name {
    return 'single-vep';
}

sub requires_experts {
    return ('single-vep');
}

sub available_fields {
    return qw/
        transcript_name
        trv_type
        amino_acid_change
        default_gene_name
        ensembl_gene_id
    /;
}

sub process_entry {
    my $self = shift;
    my $entry = shift;
    my $passed_alt_alleles = shift;

    my $vep_parser = new Genome::File::Vcf::VepConsequenceParser($entry->{header});

    my %return_values;
    for my $variant_allele (@$passed_alt_alleles) {
        my ($transcript) = $vep_parser->transcripts($entry, $variant_allele);
        $return_values{$variant_allele} = {
            transcript_name   =>$transcript->{'feature'},
            trv_type          => $transcript->{'consequence'},
            amino_acid_change => $transcript->{'hgvsp'},
            default_gene_name => $transcript->{'symbol'} ,
            ensembl_gene_id   => $transcript->{'gene'},
        };
    }

    return %return_values;
}

1;
