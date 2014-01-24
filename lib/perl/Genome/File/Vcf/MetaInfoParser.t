#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

my $class = "Genome::File::Vcf::MetaInfoParser";
use_ok($class);

my @tests = (
    {
        input => "20130805",
        expected => new Genome::File::Vcf::Header::String(content => '20130805',
            is_quoted => 0),
        description => "date",
    },
    {
        input => "ftp://ftp.ncbi.nih.gov/genbank/genomes/Eukaryotes/vertebrates_mammals/Homo_sapiens/GRCh37/special_requests/GRCh37-lite.fa.gz",
        expected => new Genome::File::Vcf::Header::String(
            content => 'ftp://ftp.ncbi.nih.gov/genbank/genomes/Eukaryotes/vertebrates_mammals/Homo_sapiens/GRCh37/special_requests/GRCh37-lite.fa.gz',
            is_quoted => 0),
        description => "url",
    },
    {
        input => "<ID=TCGA-A2-A0CO-01A-13D-A228-09,SampleUUID=36053173-6839-43ec-8157-75d729085e6b,SampleTCGABarcode=TCGA-A2-A0CO-01A-13D-A228-09,File=TCGA-A2-A0CO-01A-13D-A228-09.bam,Platform=Illumina,Source=dbGap,Accession=phs000178>",
        expected => {
            ID => new Genome::File::Vcf::Header::String(content => "TCGA-A2-A0CO-01A-13D-A228-09",
                is_quoted => 0),
            SampleUUID => new Genome::File::Vcf::Header::String(content => "36053173-6839-43ec-8157-75d729085e6b",
                is_quoted => 0),
            SampleTCGABarcode => new Genome::File::Vcf::Header::String(content => "TCGA-A2-A0CO-01A-13D-A228-09",
                is_quoted => 0),
            File => new Genome::File::Vcf::Header::String(content => "TCGA-A2-A0CO-01A-13D-A228-09.bam",
                is_quoted => 0),
            Platform => new Genome::File::Vcf::Header::String(content => "Illumina",
                is_quoted => 0),
            Source => new Genome::File::Vcf::Header::String(content => "dbGap",
                is_quoted => 0),
            Accession => new Genome::File::Vcf::Header::String(content => "phs000178",
                is_quoted => 0),
        },
        description => "sample",
    },
    {
        input => "<InputVCFSource=<Samtools>>",
        expected => {
            InputVCFSource => {
                Samtools => undef 
            }
        },
        description => "hash with flag",
    },
    {
        input => "<ID=SS,Number=1,Type=Integer,Description=\"Variant status relative to non-adjacent Normal,0=wildtype,1=germline,2=somatic,3=LOH,4=post-transcriptional modification,5=unknown\">",
        expected => {
            ID => new Genome::File::Vcf::Header::String(content => "SS",
                is_quoted => 0),
            Number => new Genome::File::Vcf::Header::String(content => "1",
                is_quoted => 0),
            Type => new Genome::File::Vcf::Header::String(content => "Integer",
                is_quoted => 0),
            Description => new Genome::File::Vcf::Header::String(content => "Variant status relative to non-adjacent Normal,0=wildtype,1=germline,2=somatic,3=LOH,4=post-transcriptional modification,5=unknown",
                is_quoted => 1),
        },
        description => "map",
    },
    {
        input => "<ID=MQ,Number=1,Type=Integer,Description=\"Phred style probability score that the variant is novel with respect to the genome\'s ancestor\">",
        expected => {
            ID => new Genome::File::Vcf::Header::String(content => "MQ",
                is_quoted => 0),
            Number => new Genome::File::Vcf::Header::String(content => "1",
                is_quoted => 0),
            Type => new Genome::File::Vcf::Header::String(content => "Integer",
                is_quoted => 0),
            Description => new Genome::File::Vcf::Header::String(content => "Phred style probability score that the variant is novel with respect to the genome\'s ancestor",
                is_quoted => 1),
        },
        description => "map with quoted string",
    },
    {
        input => "/gsc/pkg/bio/vcftools/installed/bin/vcf-annotate",
        expected => new Genome::File::Vcf::Header::String(content => "/gsc/pkg/bio/vcftools/installed/bin/vcf-annotate",
            is_quoted => 0),
        description => "file path",
    },
    {
        input => "/gsc/pkg/bio/vcftools/installed/bin/vcf-annotate -a /gscmnt/ams1102/info/model_data/2771411739/build106409619/annotation_data/tiering_bed_files_v3/tiers.bed.gz -d key=INFO,ID=TIER,Number=1,Type=Integer,Description=Location of variant by tier -c CHROM,FROM,TO,INFO/TIER",
        expected => new Genome::File::Vcf::Header::String(content => "/gsc/pkg/bio/vcftools/installed/bin/vcf-annotate -a /gscmnt/ams1102/info/model_data/2771411739/build106409619/annotation_data/tiering_bed_files_v3/tiers.bed.gz -d key=INFO,ID=TIER,Number=1,Type=Integer,Description=Location of variant by tier -c CHROM,FROM,TO,INFO/TIER",
            is_quoted => 0),
        description => "arbitrary string with = and ,",
    },
    {
        input => "<Description=\"Something\">",
        expected => {
            Description => new Genome::File::Vcf::Header::String(content => "Something", is_quoted => 1),
        },
        description => "quoted string without any spaces",
    },
);

for my $test (@tests) {
    my $input = $test->{input};
    my $expected = $test->{expected};
    my $description = $test->{description};
    my $output = $class->parse($input);
    ok($output, "Output created for $description") or diag("Parsing failed for input: $input");
    is_deeply($output, $expected, "Input parsed as expected for $description")
        or diag("Input: $input\nExpected: " .Data::Dumper::Dumper($expected) . "Got: ". Data::Dumper::Dumper($output));
}

done_testing;