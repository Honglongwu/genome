#!/usr/bin/env genome-perl

use strict;
use warnings FATAL => 'all';

BEGIN {
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

BEGIN {
    use above 'Genome';

    use Test::More;
    if (Genome::Config->arch_os ne 'x86_64') {
       plan skip_all => 'requires 64-bit machine';
    }
    else {
       plan tests => 13;
    }
};

BEGIN {
    use_ok('Genome::Model::Tools::Picard::SamToFastq');
};

use File::Temp;
use Path::Class qw(dir file);

# data here is first 100 lines from lane 1 of
# /gscmnt/sata604/hiseq2000/100218_P21_0393_AFC20GF1/Data/Intensities/Basecalls/GERALD_30-03-2010_lims
# see FastqToSam.t
my $dir = dir(
    $ENV{GENOME_TEST_INPUTS} . '/Genome-Model-Tools-Picard-FastqToSam');

my $tmpdir = dir(Genome::Sys->create_temp_directory);
my $fq1    = $tmpdir->file('s_1_1_sequence.txt');
my $fq2    = $tmpdir->file('s_1_2_sequence.txt');
my $bam    = $dir->file('gerald_20GF1_1.bam');

my $cmd_1  = Genome::Model::Tools::Picard::StandardSamToFastq->create(
    input  => $bam . '',
    fastq  => $fq1 . '',
    second_end_fastq => $fq2 . '',
    re_reverse => 1,
);
isa_ok($cmd_1, 'Genome::Model::Tools::Picard::StandardSamToFastq');
ok( $cmd_1->execute, 'execute' );
ok( -s $fq1,         'output file is non-zero' );
ok( -s $fq2,         'output file is non-zero' );
unlink($fq1->stringify, $fq2->stringify);

my $cmd_2  = Genome::Model::Tools::Picard::StandardSamToFastq->create(
    input  => $bam . '',
    fastq  => $fq1 . '',
    second_end_fastq => $fq2 . '',
    re_reverse => 1,
    use_version => '1.77'
);

isa_ok($cmd_2, 'Genome::Model::Tools::Picard::StandardSamToFastq');
ok( $cmd_2->execute, 'execute' );
ok( -s $fq1,         'output file is non-zero' );
ok( -s $fq2,         'output file is non-zero' );
unlink($fq1->stringify, $fq2->stringify);

my $cmd_3  = Genome::Model::Tools::Picard::StandardSamToFastq->create(
    input  => $bam . '',
    fastq  => $fq1 . '',
    second_end_fastq => $fq2 . '',
    re_reverse => 1,
    use_version => '1.113'
);
isa_ok($cmd_3, 'Genome::Model::Tools::Picard::StandardSamToFastq');
ok( $cmd_3->execute, 'execute' );
ok( -s $fq1,         'output file is non-zero' );
ok( -s $fq2,         'output file is non-zero' );
unlink($fq1->stringify, $fq2->stringify);


$tmpdir->rmtree;
