#!/usr/bin/env genome-perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use above 'Genome';

use Data::Dumper;
use Test::MockObject;
use Test::More;

use_ok('Genome::Model::Command::Services::AssignQueuedInstrumentData') or die;

my $cnt = 0;
my (@samples, @instrument_data);
no warnings;
*Genome::InstrumentDataAttribute::get = sub {
    my ($class, %params) = @_;
    my %attrs = map { $_->id => $_ } map { $_->attributes } @instrument_data;
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

my @projects;
push @projects, Genome::Project->create( id => -444, name => 'PCGP__TEST_PROJECT__');
ok( $projects[0], 'create project for research project' );
push @projects, Genome::Project->create( id => -222, name => '__TEST_WORKORDER__');
ok( $projects[1], 'create project for work order' );
my @model_groups = Genome::ModelGroup->get(uuid => [ map { $_->id } @projects ]);
is(@model_groups, 2, 'created model groups');

my $bac_source = Genome::Individual->__define__(
    name => '__TEST_SOURCE__', 
    taxon => Genome::Taxon->__define__(name => 'human', domain => 'Human', species_latin_name => 'Homo sapiens'),
);
ok($bac_source, 'define pcgp source');
ok($bac_source->taxon, 'define pcgp taxon');
my $pp_id = 2644306;
my $pp = Genome::ProcessingProfile->get($pp_id);
ok($pp, 'got pcgp pp');
ok(_create_inst_data($bac_source), 'create inst data for pcgp taxon');
is(@instrument_data, $cnt, "create $cnt inst data");

my $cmd = Genome::Model::Command::Services::AssignQueuedInstrumentData->create;
ok($cmd, 'create aqid');
$cmd->dump_status_messages(1);
ok($cmd->execute, 'execute');
my @new_models = values %{$cmd->_newly_created_models};
my %new_models = _model_hash(@new_models);
my @existing_models = values %{$cmd->_existing_models_assigned_to};
my %existing_models = _model_hash(@existing_models);
#print Dumper(\%new_models,\%existing_models);
is_deeply(
    \%new_models,
    {
        "AQID-testsample1.human.prod-refalign" => {
            subject => $samples[0]->name,
            processing_profile_id => $pp_id,
            inst => [ $instrument_data[0]->id ],
            auto_assign_inst_data => 1,
            projects => [ sort map { $_->id } @projects ],
            model_groups => [ sort map { $_->id } @model_groups ],
        },
    },
    'new models',
);
is_deeply(
    [ map { $_->attribute_value } map { $_->attributes(attribute_label => 'tgi_lims_status') } @instrument_data ],
    [ map { 'processed' } @instrument_data ],
    'set tgi lims status to processed for all instrument data',
);

done_testing();


sub _create_inst_data {
    my $source = shift;
    $cnt++;
    my $sample = Genome::Sample->__define__(
        name => 'AQID-testsample'.$cnt.'.'.lc($source->taxon->name),
        source => $source,
        extraction_type => 'genomic',
    );
    ok($sample, 'sample '.$cnt);
    push @samples, $sample;
    my $library = Genome::Library->__define__(
        name => $sample->name.'-testlib',
        sample_id => $sample->id,
    );
    ok($library, 'create library '.$cnt);

    my $instrument_data = Genome::InstrumentData::Solexa->__define__(
        library_id => $library->id,
    );
    ok($instrument_data, 'created instrument data '.$cnt);
    push @instrument_data, $instrument_data;
    $instrument_data->add_attribute(
        attribute_label => 'tgi_lims_status',
        attribute_value => 'new',
    );
    for my $project ( @projects ) {
        $project->add_part(
            entity_id => $instrument_data->id,
            entity_class_name => 'Genome::InstrumentData',
            label => 'instrument_data',
        );
    }

    return 1;
}

sub _model_hash {
    return map { 
        $_->name => { 
            subject => $_->subject_name, 
            processing_profile_id => $_->processing_profile_id,
            inst => [ map { $_->id } $_->instrument_data ],
            auto_assign_inst_data => $_->auto_assign_inst_data,
            projects => [ sort map { $_->id } $_->projects ],
            model_groups => [ sort map { $_->id } $_->model_groups ],
        }
    } @_;
}