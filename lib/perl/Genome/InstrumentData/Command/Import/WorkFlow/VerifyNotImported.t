#! /gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

require Genome::Utility::Test;
require File::Temp;
use Test::More;

use_ok('Genome::InstrumentData::Command::Import::WorkFlow::VerifyNotImported') or die;
my $test_dir = Genome::Utility::Test->data_dir_ok('Genome::InstrumentData::Command::Import', 'bam/v1') or die;

# Run MD5
my $original_path = $test_dir.'/input.bam';
my $tmp_dir = File::Temp::tempdir(CLEANUP => 1);
my $source_path = $tmp_dir.'/input.bam';
symlink($original_path, $source_path);
my $cmd = Genome::InstrumentData::Command::Import::WorkFlow::VerifyNotImported->execute(
    working_directory => $tmp_dir,
    source_path => $source_path,
);
ok($cmd, 'execute');
my $md5_path = $cmd->source_md5_path;
is($md5_path, $cmd->helpers->md5_path_for($cmd->source_path), 'md5 path named correctly');
ok(-s $md5_path, 'md5 path exists');

# Load MD5
my $original_md5_path = $cmd->original_md5_path;
is($original_md5_path, $cmd->helpers->original_md5_path_for($cmd->source_path), 'original md5 path named correctly');
rename($md5_path, $original_md5_path);
ok(-s $original_md5_path, 'renamed md5 to valid original md5 path');
$cmd = Genome::InstrumentData::Command::Import::WorkFlow::VerifyNotImported->execute(
    working_directory => $tmp_dir,
    source_path => $source_path,
);
ok($cmd, 'execute');
$md5_path = $cmd->source_md5_path;
is($md5_path, $cmd->helpers->md5_path_for($cmd->source_path), 'md5 path named correctly');
ok(-s $md5_path, 'md5 path exists');

# Previously Imported MD5
my $md5_attr = Genome::InstrumentDataAttribute->__define__(
    instrument_data_id => -11,
    attribute_label => 'original_data_path_md5',
    attribute_value => '940825168285c254b58c47399a3e1173',
    nomenclature => 'WUGC',
);
ok($md5_attr, 'create md5 inst data attr');
$cmd = Genome::InstrumentData::Command::Import::WorkFlow::VerifyNotImported->execute(
    working_directory => $tmp_dir,
    source_path => $source_path,
);
ok(!$cmd->result, 'execute');
is(Genome::InstrumentData::Command::Import::WorkFlow::Helpers->get->error_message, 'Instrument data was previously imported! Found existing instrument data with MD5s: -11 => 940825168285c254b58c47399a3e1173', 'correct error');

# Invalid MD5
unlink($original_md5_path);
Genome::Sys->create_symlink($test_dir.'/invalid.md5', $original_md5_path);
ok(-s $original_md5_path, 'linked invalid original md5 path') or die;
$cmd = Genome::InstrumentData::Command::Import::WorkFlow::VerifyNotImported->execute(
    working_directory => $tmp_dir,
    source_path => $source_path,
);
ok(!$cmd->result, 'execute');
is($cmd->error_message, 'Original and generated MD5s do not match! 040825168285c254b58c47399a3e1173 vs. 940825168285c254b58c47399a3e1173', 'correct error');

#print "$tmp_dir\n"; <STDIN>;
done_testing();
