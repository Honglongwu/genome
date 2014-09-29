#!/usr/bin/env genome-perl

use strict;
use warnings FATAL => 'all';

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above "Genome";
use Test::More;
use Test::Exception;
use Genome::Utility::Test qw(compare_ok);
use Set::Scalar;
#use Test::Exception; #  lives/dies_ok { $foo->method } 'this died'; throws_ok( sub { $foo->method }, qw/an error/, 'caught');
#use Sub::Install; # Sub::Install::install_sub({code => sub {} , into => $package, as => $subname});
#use Test::MockObject::Extends; # my $o = T:MO:E->new($obj); $o->mock($methodname, sub { }); $o->unmock($methodname);

my $pkg = 'Genome::VariantReporting::Command::CombineReports';
use_ok($pkg) or die;
my $data_dir = __FILE__.".d";

subtest "test with headers" => sub {
    my $report_a = File::Spec->join($data_dir, 'report_a.header');
    my $report_b = File::Spec->join($data_dir, 'report_b.header');
    my $expected = File::Spec->join($data_dir, 'expected.header');

    my $output_file = Genome::Sys->create_temp_file_path;
    my $cmd = $pkg->create(reports => [$report_a, $report_b], sort_columns => ['chr', 'pos'], contains_header => 1, output_file => $output_file);
    isa_ok($cmd, $pkg);

    my @expected_header = qw(chr pos data1 data2);
    is_deeply([$cmd->get_header($report_a)], \@expected_header, 'Header looks as expected');
    is_deeply([$cmd->get_master_header], \@expected_header, 'Master header looks as expected');

    is_deeply([$cmd->get_sort_column_numbers], [1,2], 'get_sort_column_numbers works');
    is($cmd->get_sort_params, '-V -k1 -k2', 'get_sort_params works');

    ok($cmd->execute, 'Executed the test command');
    compare_ok($output_file, $expected, 'Output file looks as expected');
};

subtest "test with headers with source" => sub {
    my $report_a = File::Spec->join($data_dir, 'report_a.header');
    my $report_b = File::Spec->join($data_dir, 'report_b.header');
    my $expected = File::Spec->join($data_dir, 'expected_with_source.header');

    my $output_file = Genome::Sys->create_temp_file_path;
    my $cmd = $pkg->create(
        reports => [$report_a, $report_b],
        sort_columns => ['chr', 'pos'],
        contains_header => 1,
        output_file => $output_file,
        entry_sources => {
            File::Spec->join($data_dir, 'report_a.header') => "report_a",
            File::Spec->join($data_dir, 'report_b.header') => "report_b"
        }
    );
    isa_ok($cmd, $pkg);

    my @expected_header = qw(chr pos data1 data2);
    is_deeply([$cmd->get_header($report_a)], \@expected_header, 'Header looks as expected');
    is_deeply([$cmd->get_master_header], \@expected_header, 'Master header looks as expected');

    is_deeply([$cmd->get_sort_column_numbers], [1,2], 'get_sort_column_numbers works');
    is($cmd->get_sort_params, '-V -k1 -k2', 'get_sort_params works');

    ok($cmd->execute, 'Executed the test command');
    compare_ok($output_file, $expected, 'Output file looks as expected');
};

subtest "test with different orders of headers" => sub {
    my $report_a = File::Spec->join($data_dir, 'report_a.header');
    my $report_b = File::Spec->join($data_dir, 'report_b2.header');
    my $expected = File::Spec->join($data_dir, 'expected.header');

    my $output_file = Genome::Sys->create_temp_file_path;
    my $cmd = $pkg->create(reports => [$report_a, $report_b], sort_columns => ['chr', 'pos'], contains_header => 1, output_file => $output_file);
    isa_ok($cmd, $pkg);

    my @expected_header = qw(chr pos data1 data2);
    is_deeply([$cmd->get_header($report_a)], \@expected_header, 'Header looks as expected');
    is_deeply([$cmd->get_master_header], \@expected_header, 'Master header looks as expected');

    is_deeply([$cmd->get_sort_column_numbers], [1,2], 'get_sort_column_numbers works');
    is($cmd->get_sort_params, '-V -k1 -k2', 'get_sort_params works');

    ok($cmd->execute, 'Executed the test command');
    compare_ok($output_file, $expected, 'Output file looks as expected');
};

subtest "test without headers" => sub {
    my $report_a = File::Spec->join($data_dir, 'report_a.noheader');
    my $report_b = File::Spec->join($data_dir, 'report_b.noheader');
    my $expected = File::Spec->join($data_dir, 'expected.noheader');

    my $output_file = Genome::Sys->create_temp_file_path;
    my $cmd = $pkg->create(reports => [$report_a, $report_b], sort_columns => ['1', '2'], contains_header => 0, output_file => $output_file);
    isa_ok($cmd, $pkg);

    my @expected_header = qw(1 2 3 4);
    is_deeply([$cmd->get_header($report_a)], \@expected_header, 'Header looks as expected');
    is_deeply([$cmd->get_master_header], \@expected_header, 'Master header looks as expected');

    is_deeply([$cmd->get_sort_column_numbers], [1,2], 'get_sort_column_numbers works');
    is($cmd->get_sort_params, '-V -k1 -k2', 'get_sort_params works');

    ok($cmd->execute, 'Executed the test command');
    compare_ok($output_file, $expected, 'Output file looks as expected');
};

subtest "test without headers with source" => sub {
    my $report_a = File::Spec->join($data_dir, 'report_a.noheader');
    my $report_b = File::Spec->join($data_dir, 'report_b.noheader');
    my $expected = File::Spec->join($data_dir, 'expected_with_source.noheader');

    my $output_file = Genome::Sys->create_temp_file_path;
    my $cmd = $pkg->create(
        reports => [$report_a, $report_b],
        sort_columns => ['1', '2'],
        contains_header => 0,
        output_file => $output_file,
        entry_sources => {
            File::Spec->join($data_dir, 'report_a.noheader') => "report_a",
            File::Spec->join($data_dir, 'report_b.noheader') => "report_b"
        }
    );
    isa_ok($cmd, $pkg);

    my @expected_header = qw(1 2 3 4);
    is_deeply([$cmd->get_header($report_a)], \@expected_header, 'Header looks as expected');
    is_deeply([$cmd->get_master_header], \@expected_header, 'Master header looks as expected');

    is_deeply([$cmd->get_sort_column_numbers], [1,2], 'get_sort_column_numbers works');
    is($cmd->get_sort_params, '-V -k1 -k2', 'get_sort_params works');

    ok($cmd->execute, 'Executed the test command');
    compare_ok($output_file, $expected, 'Output file looks as expected');
};

subtest "Source tags must be defined" => sub {
    my $cmd = $pkg->create(reports => ["report1", "report2"], output_file => "output", entry_sources => {"report2" => "report2"});
    throws_ok(sub {$cmd->validate}, qr(No source tag defined for report report1), "Error if source tag is not defined for one report");
};

subtest "columns to split only works with headers" => sub {
    my $report_a = File::Spec->join($data_dir, 'report_a.noheader');
    my $report_b = File::Spec->join($data_dir, 'report_b.noheader');
    my $expected = File::Spec->join($data_dir, 'expected.noheader');

    my $output_file = Genome::Sys->create_temp_file_path;
    my $cmd = $pkg->create(
        reports => [$report_a, $report_b],
        sort_columns => ['1', '2'],
        contains_header => 0,
        output_file => $output_file,
        split_indicators => ["split"]
    );
    isa_ok($cmd, $pkg);

    throws_ok(sub {$cmd->execute}, qr/If split_indicators are specified, then a header must be present/, 'columns_to_split fails without header');
};

subtest "with split" => sub {
    my $report_c = File::Spec->join($data_dir, 'report_c.header');
    my $expected = File::Spec->join($data_dir, 'expected_split.header');

    my $output_file = Genome::Sys->create_temp_file_path;
    my $cmd = $pkg->create(
        reports => [$report_c],
        sort_columns => ['chr', 'pos'],
        contains_header => 1,
        output_file => $output_file,
        split_indicators => ["split"]
    );
    isa_ok($cmd, $pkg);

    my @expected_header = qw(chr pos data1 data2 split1 split2);
    is_deeply([$cmd->get_header($report_c)], \@expected_header, 'Header looks as expected');
    is_deeply([$cmd->get_master_header], \@expected_header, 'Master header looks as expected');

    is_deeply([$cmd->get_sort_column_numbers], [1,2], 'get_sort_column_numbers works');
    is($cmd->get_sort_params, '-V -k1 -k2', 'get_sort_params works');

    ok($cmd->execute, 'Executed the test command');
    compare_ok($output_file, $expected, 'Output file looks as expected');
};
done_testing();