#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above "Genome";

use Test::More;

use_ok('Genome::InstrumentData::Command::Import::Basic') or die;

my $sample = Genome::Sample->create(name => '__TEST_SAMPLE__');
ok($sample, 'Create sample');

my @source_files = (
    $ENV{GENOME_TEST_INPUTS} . '/Genome-InstrumentData-Command-Import-Fastq/s_5_1_sequence.txt', 
    $ENV{GENOME_TEST_INPUTS} . '/Genome-InstrumentData-Command-Import-Fastq/s_5_2_sequence.txt',
);

# Fails
my $fail = Genome::InstrumentData::Command::Import::Basic->create(
    sample => $sample,
    source_files => [ 'blah.fastq' ],
    import_source_name => 'broad',
    sequencing_platform => 'solexa',
    instrument_data_properties => [qw/ lane=2 flow_cell_id=XXXXXX /],
);
ok(!$fail->execute, 'Fails w/ invalid files');
my $error = $fail->error_message;
is($error, 'Source file does not exist! blah.fastq', 'Correct error meassage');

$fail = Genome::InstrumentData::Command::Import::Basic->create(
    sample => $sample,
    source_files => [ 'blah' ],
    import_source_name => 'broad',
    sequencing_platform => 'solexa',
    instrument_data_properties => [qw/ lane=2 flow_cell_id=XXXXXX /],
);
ok(!$fail->execute, 'Fails w/ no suffix');
$error = $fail->error_message;
is($error, 'Failed to get suffix from source file! blah', 'Correct error meassage');

$fail = Genome::InstrumentData::Command::Import::Basic->create(
    sample => $sample,
    source_files => \@source_files,
    import_source_name => 'broad',
    sequencing_platform => 'solexa',
    instrument_data_properties => [qw/ lane= /],
);
ok(!$fail->execute, 'Fails w/ invalid instrument_data_properties');
$error = $fail->error_message;
is($error, 'Failed to parse with instrument data property name/value! lane=', 'Correct error meassage');

$fail = Genome::InstrumentData::Command::Import::Basic->create(
    sample => $sample,
    source_files => \@source_files,
    import_source_name => 'broad',
    sequencing_platform => 'solexa',
    instrument_data_properties => [qw/ lane=2 lane=3 /],
);
ok(!$fail->execute, 'Fails w/ invalid instrument_data_properties');
$error = $fail->error_message;
is($error, 'Multiple values for instrument data property! lane => 2, 3', 'Correct error meassage');

# Success
my $cmd = Genome::InstrumentData::Command::Import::Basic->create(
    sample => $sample,
    source_files => \@source_files,
    import_source_name => 'broad',
    sequencing_platform => 'solexa',
    instrument_data_properties => [qw/ lane=2 flow_cell_id=XXXXXX /],
);
ok($cmd, "create import command");
ok($cmd->execute, "excute import command");

my $instrument_data = $cmd->instrument_data;
ok($instrument_data, 'got instrument data');
is($instrument_data->original_data_path, join(',', @source_files), 'original_data_path correctly set');
is($instrument_data->import_format, 'sanger fastq', 'import_format correctly set');
is($instrument_data->sequencing_platform, 'solexa', 'sequencing_platform correctly set');
is($instrument_data->is_paired_end, 1, 'is_paired_end correctly set');
is($instrument_data->read_count, 2000, 'read_count correctly set');
my $allocation = $instrument_data->allocations;
ok($allocation, 'got allocation');
ok($allocation->kilobytes_requested > 0, 'allocation kb was set');
my $archive_path = $instrument_data->attributes(attribute_label => 'archive_path')->attribute_value;
ok($archive_path, 'got archive path');
ok(-s $archive_path, 'archive path exists');
is($archive_path, $allocation->absolute_path.'/archive.tgz', 'archive path named correctly');

# Reimport fails
$fail = Genome::InstrumentData::Command::Import::Basic->create(
    sample => $sample,
    source_files => \@source_files,
    import_source_name => 'broad',
    sequencing_platform => 'solexa',
    instrument_data_properties => [qw/ lane=2 flow_cell_id=XXXXXX /],
);
ok(!$fail->execute, "Failed to reimport");
$error = $fail->error_message;
like($error, qr/^Found existing instrument data for library and source files. Were these previously imported\? Exiting instrument data id:/, 'Correct error meassage');

#print $cmd->instrument_data->allocations->absolute_path."\n"; <STDIN>;
done_testing();
exit;

