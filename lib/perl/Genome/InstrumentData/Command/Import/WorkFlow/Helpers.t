#! /gsc/bin/perl

BEGIN {
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above 'Genome';

require File::Temp;
require Genome::Utility::Test;
use Test::Exception;
use Test::More;

my $class = 'Genome::InstrumentData::Command::Import::WorkFlow::Helpers';
use_ok('Genome::InstrumentData::Command::Import::WorkFlow::Helpers') or die;
use_ok($class) or die;
my $test_dir = Genome::Utility::Test->data_dir_ok('Genome::InstrumentData::Command::Import') or die;

my $helpers = $class->get;
ok($helpers, 'get helpers');

# source files functions
my @source_files = (
    $ENV{GENOME_TEST_INPUTS} . '/Genome-InstrumentData-Command-Import-Basic/fastq-1.fq.gz',
    $ENV{GENOME_TEST_INPUTS} . '/Genome-InstrumentData-Command-Import-Basic/fastq-2.fastq',
);

# source file format
ok(!eval{$helpers->source_file_format()}, 'format for no source file fails');
ok(!$helpers->source_file_format('source.duh'), 'no format for unknown source file');
is($helpers->error_message, 'Unrecognized source file format! source.duh', 'correct error');
is($helpers->source_file_format($source_files[0]), 'fastq', 'source file 1 format');
is($helpers->source_file_format($source_files[1]), 'fastq', 'source file 2 format');
is($helpers->source_file_format('source_file.fastq.tgz'), 'fastq', 'format for tgz source file is fastq');
is($helpers->source_file_format('source_file.fastq.tar.gz'), 'fastq', 'format for tar.gz source file is fastq');
is($helpers->source_file_format('source.bam'), 'bam', 'format for bam source file is bam');
is($helpers->source_file_format('source.sra'), 'sra', 'format for sra source file is sra');
is($helpers->source_file_format('source.fasta'), 'fasta', 'format for fasta source file is fasta');
is($helpers->source_file_format('source.fa'), 'fasta', 'format for fa source file is fasta');
is($helpers->source_file_format('source.fna'), 'fasta', 'format for fna source file is fasta');

ok(!eval{$helpers->size_of_source_file;}, 'failed to get size for source file w/o source file');
ok(!eval{$helpers->size_of_remote_file;}, 'failed to get size for remote file w/o remote file');

ok(!eval{$helpers->kilobytes_required_for_processing_of_source_files;}, 'failed to get kilobytes needed for processing w/o source files');
is($helpers->kilobytes_required_for_processing_of_source_files(@source_files), 738, 'kilobytes needed for processing source files');

# headers
ok(!eval{$helpers->load_headers_from_bam;}, 'failed to get headers w/o bam');
my $input_bam = $test_dir.'/bam-rg-multi/v1/input.rg-multi.bam';
ok(-s $input_bam, 'input bam');
my $headers = $helpers->load_headers_from_bam($input_bam);
is_deeply(
    $headers,
    {
        '@SQ' => [
            'SN:MT	LN:16299	UR:ftp://ftp.ncbi.nih.gov/genbank/genomes/Eukaryotes/vertebrates_mammals/Homo_sapiens/GRCh37/special_requests/GRCh37-lite.fa.gz	AS:GRCh37-lite	M5:c68f52674c9fb33aef52dcf399755519	SP:Mus musculus'
        ],
        '@PG' => [
            'ID:2883581797	VN:0.5.9	CL:bwa aln -t4 -q 5; bwa sampe  -a 435.616825 ',
            'ID:2883581798	VN:0.5.9	CL:bwa aln -t4 -q 5; bwa sampe  -a 435.616825 ',
            'ID:GATK PrintReads	VN:f6dac2d	CL:readGroup=null platform=null number=-1 downsample_coverage=1.0 sample_file=[] sample_name=[] simplify=false no_pg_tag=false'
        ],
        '@HD' => [ 'VN:1.4	GO:none	SO:coordinate' ],
        '@RG' => [
            'ID:2883581797	PL:illumina	PU:2883581797.	LB:TEST-patient1-somval_normal1-extlibs	PI:165	DS:paired end	DT:2012-12-17T13:15:46-0600	SM:TEST-patient1-somval_normal1	CN:WUGSC',
            'ID:2883581798	PL:illumina	PU:2883581798.	LB:TEST-patient1-somval_normal1-extlibs	PI:165	DS:paired end	DT:2012-12-17T13:15:46-0600	SM:TEST-patient1-somval_normal1	CN:WUGSC',
            'ID:2883581799	PL:illumina	PU:2883581799.	LB:TEST-patient1-somval_normal1-extlibs	PI:165	DS:paired end	DT:2012-12-17T13:15:46-0600	SM:TEST-patient1-somval_normal1	CN:WUGSC',
        ],
    },
    'headers',
);

ok(!eval{$helpers->read_groups_from_headers;}, 'failed to get read groups from headers w/o headers');
my $read_groups_from_headers = $helpers->read_groups_from_headers($headers->{'@RG'});
is_deeply(
    $read_groups_from_headers, 
    {
        2883581797 => 'CN:WUGSC	DS:paired end	DT:2012-12-17T13:15:46-0600	LB:TEST-patient1-somval_normal1-extlibs	PI:165	PL:illumina	PU:2883581797.	SM:TEST-patient1-somval_normal1',
        2883581798 => 'CN:WUGSC	DS:paired end	DT:2012-12-17T13:15:46-0600	LB:TEST-patient1-somval_normal1-extlibs	PI:165	PL:illumina	PU:2883581798.	SM:TEST-patient1-somval_normal1',
        2883581799 => 'CN:WUGSC	DS:paired end	DT:2012-12-17T13:15:46-0600	LB:TEST-patient1-somval_normal1-extlibs	PI:165	PL:illumina	PU:2883581799.	SM:TEST-patient1-somval_normal1',
    },
    'read groups from headers',
);

ok(!eval{$helpers->headers_to_string;}, 'failed headers to string w/o headers');
my $headers_string = $helpers->headers_to_string($headers);
ok($headers_string, 'headers to string');# cannot compare for some reason

ok(!eval{$helpers->load_read_groups_from_bam;}, 'failed to load read groups from bam w/o bam');
is_deeply($helpers->load_read_groups_from_bam($test_dir.'/sra/v1/input.sra.bam'), [], 'non read groups in bam');
is_deeply($helpers->load_read_groups_from_bam($input_bam), [qw/ 2883581797 2883581798 2883581799 /], 'load read groups from bam');

# verify tmp disk
ok($helpers->verify_adequate_disk_space_is_available_for_source_files(working_directory => '/tmp', source_files => \@source_files), 'verify adequate disk space is available for source files');

# flagstat
my $bam_basename = 'input.bam';
my $tmp_dir = File::Temp::tempdir(CLEANUP => 1);
my $bam_path = $tmp_dir.'/'.$bam_basename;
Genome::Sys->create_symlink($test_dir.'/bam/v1/'.$bam_basename, $bam_path);
ok(-s $bam_path, 'linked bam path');
my $run_flagstat = $helpers->load_or_run_flagstat($bam_path); # runs
ok($run_flagstat, 'run flagstat');
my $load_flagstat = $helpers->load_or_run_flagstat($bam_path); # loads
is_deeply($load_flagstat, $run_flagstat, 'load flagstat');
ok($helpers->validate_bam($bam_path), 'validate bam');

# md5
throws_ok { $helpers->md5_path_for } qr/^No path given to get md5 path!/, 'failed md5_path_for undef';
is($helpers->md5_path_for($bam_path), $bam_path.'.md5', 'md5_path_for');
throws_ok { $helpers->original_md5_path_for } qr/^No path given to get original md5 path!/, 'failed original_data_path_md5 undef';
is($helpers->original_md5_path_for($bam_path), $bam_path.'.md5-orig', 'original_md5_path_for');

my $run_md5 = $helpers->load_or_run_md5($bam_path); # runs
ok($run_md5, 'run md5');
my $load_md5 = $helpers->load_or_run_md5($bam_path); # loads
is_deeply($load_md5, $run_md5, 'load md5');

# previously imported
my @md5s = map { $_ x 32 } (qw/ a b c /);
ok(!$helpers->were_original_path_md5s_previously_imported(@md5s), 'as expected, no inst data found for md5s');
my @mdr_attrs = map { 
    Genome::InstrumentDataAttribute->create(
    instrument_data_id => $_ - 11,
    attribute_label => 'original_data_path_md5',
    attribute_value => $md5s[$_],
    nomenclature => 'WUGC',
) } ( 0..1); # none for c
ok($helpers->were_original_path_md5s_previously_imported(@md5s), 'inst data found for md5s "a" & "b"');
is($helpers->error_message, 'Instrument data was previously imported! Found existing instrument data with MD5s: -10 => bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, -11 => aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'correct error message');
ok(!$helpers->were_original_path_md5s_previously_imported($md5s[2]), 'as expected, no inst data found for "c" md5');

# properties
my $properties = $helpers->key_value_pairs_to_hash(qw/ sequencing_platform=solexa lane=2 flow_cell_id=XXXXXX /);
is_deeply(
    $properties,
    { sequencing_platform => 'solexa', lane => 2, flow_cell_id => 'XXXXXX', },
    'key value piars to hash',
);
$properties = $helpers->key_value_pairs_to_hash(qw/ sequencing_platform=solexa lane=2 lane=3 flow_cell_id=XXXXXX /);
ok(!$properties, 'failed as expected to convert key value pairsr into hash with duplicate label');
is($helpers->error_message, "Multiple values for instrument data property! lane => 2, 3", 'correct error');
$properties = $helpers->key_value_pairs_to_hash(qw/ sequencing_platform=solexa lane= flow_cell_id=XXXXXX /);
is($helpers->error_message, 'Failed to parse with instrument data property label/value! lane=', 'correct error');

# rm source files
ok(!eval{$helpers->remove_path_and_auxiliary_files();}, 'failed to remove source paths and md5s w/o source paths');
Genome::Sys->create_symlink($test_dir.'/bam/v1/'.$bam_basename.'.md5-orig', $bam_path.'.md5-orig');
Genome::Sys->create_symlink($test_dir.'/bam/v1/'.$bam_basename.'.md5-orig', $bam_path.'.random');
ok($helpers->remove_paths_and_auxiliary_files($bam_path), 'remove source paths and md5s w/o source paths');
ok(!glob($bam_path.'*'), 'removed path and auxillary files');

done_testing();
