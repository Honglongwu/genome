package Genome::Config::AnalysisProject;

use strict;
use warnings;

use Genome;

class Genome::Config::AnalysisProject {
    is => 'Genome::Utility::ObjectWithTimestamps',
    id_generator => '-uuid',
    data_source => 'Genome::DataSource::GMSchema',
    table_name => 'GENOME_CONFIG_ANALYSIS_PROJECT',
    id_by => [
        id => {
            is => 'Text',
        },
    ],
    has => [
        _configuration_set_id => {
            is => 'Text',
            column_name => 'configuration_set_id',
        },
        _configuration_set => {
            is => 'Genome::Config::Set',
            id_by => '_configuration_set_id',
        },
        created_by => {
            is => 'Text',
        },
        _analysis_menu_item_id => {
            is => 'Text',
            column_name => 'analysis_menu_item_id',
        },
        _analysis_menu_item => {
            is => 'Genome::Config::AnalysisMenuItem',
            id_by => '_analysis_menu_item_id',
        },
        name => {
            is => 'Text',
        },
    ],
    has_transient_optional => [
        configuration_reader => {
            is => 'Genome::Config::MaskedConfigurationReader',
        },
    ],
};

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    eval {
        $self->_create_configuration_set();
    };
    if(my $error = $@) {
        $self->delete();
        die($error);
    }
    return $self;
}

sub _create_configuration_set {
    my $self = shift;
    my $set = Genome::Config::Set->create();
    $self->_configuration_set($set);
}

sub get_configuration_reader {
    my $self = shift;

    unless($self->configuration_reader) {
        $self->configuration_reader(Genome::Config::MaskedConfigurationReader->create(
            config_handler              => Genome::Config::Handler::TreeHandler->create(
                                                base_path => $self->_configuration_set->path
                                           ),
            mask_handler                => Genome::Config::Handler::TreeHandler->create(
                                                base_path => $self->_analysis_menu_item->path
                                           ),
            default_handler             => Genome::Config::Handler::TreeHandler->create(
                                                base_path => $ENV{GENOME_ANALYSIS_PROJECT_DEFAULTS}
                                           ),
            configuration_parser        => Genome::Config::Parser::YAML->create(),
            configuration_copy_strategy => Genome::Config::CopyStrategy::TreeCopy->create(),
        ));
    }
    return $self->configuration_reader;
}

1;
