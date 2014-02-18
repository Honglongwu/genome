#!/usr/bin/env genome-perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use above 'Genome';

use Test::More;

use_ok('Genome::Model::Command::Services::AssignQueuedInstrumentData') or die;

my $instrument_data;
no warnings;
*Genome::InstrumentDataAttribute::get = sub {
    my ($class, %params) = @_;
    my %attrs = map { $_->id => $_ } $instrument_data->attributes;
    for my $param_key ( keys %params ) {
        my @param_values = ( ref $params{$param_key} ? @{$params{$param_key}} : $params{$param_key} );
        my @unmatched_attrs;
        for my $attr ( values %attrs ) {
            next if grep { $attr->$param_key eq $_ } @param_values;
            push @unmatched_attrs, $attr->id;
        }
        for ( @unmatched_attrs ) { delete $attrs{$_} }
    }
    return values %attrs;
};
use warnings;

# Skip - 454 non rna/mc16s
my $taxon = Genome::Taxon->__define__(name => '__TEST_TAXON__');
ok($taxon, 'define taxon');
my $source = Genome::Individual->__define__(name => '__TEST_SOURCE__', taxon => $taxon);
ok($source, 'define source');
my $sample = Genome::Sample->__define__(name => '__TEST_SAMPLE__', source => $source);
ok($sample, 'define sample');
my $library = Genome::Library->__define__(name => '__TEST_SAMPLE__-testlib', sample => $sample);
ok($library, 'define library');
$library->sample_id($sample->id);
$instrument_data = Genome::InstrumentData::454->__define__(
    id => '-123456',
    library_id => $library->id,
);
ok($instrument_data, 'defined instrument data');
$instrument_data->add_attribute(
    attribute_label => 'tgi_lims_status',
    attribute_value => 'new',
);
is($instrument_data->attributes(attribute_label => 'tgi_lims_status')->attribute_value, 'new', 'instrument data tgi_lims_status is new');

my $cmd = Genome::Model::Command::Services::AssignQueuedInstrumentData->create;
ok($cmd, 'create aqid');
ok($cmd->execute, 'execute');
is($instrument_data->attributes(attribute_label => 'tgi_lims_status')->attribute_value, 'skipped', 'instrument data tgi_lims_status is skipped');

done_testing();