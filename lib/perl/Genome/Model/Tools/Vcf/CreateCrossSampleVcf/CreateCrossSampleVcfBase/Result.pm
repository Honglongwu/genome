package Genome::Model::Tools::Vcf::CreateCrossSampleVcf::CreateCrossSampleVcfBase::Result;

use Genome;
use strict;
use warnings;
use Carp;

class Genome::Model::Tools::Vcf::CreateCrossSampleVcf::CreateCrossSampleVcfBase::Result {
    is => 'Genome::SoftwareResult::DiskAllocationStaged',
    is_abstract => 1,

    has_input => [
        builds => {
            is => 'Genome::Model::Build',
            is_many => 1,
        },
    ],
    has_param => [
        max_files_per_merge => { is => 'Text' },
        roi_list => { is => 'Genome::FeatureList', is_optional => 1 },
        forced_variations_build_id => { is => 'Text', is_optional => 1 },
        wingspan => { is => 'Text', is_optional => 1 },
        allow_multiple_processing_profiles => { is => 'Boolean' },
        joinx_version => { is => 'Text' },
    ],
};

sub _generate_result {
#define in subclasses
    my ($self, $staging_directory) = @_;
    my @builds = $self->builds;
    # FIXME pass command in, as non-input and non-param but required.
    my $cmd = Genome::Model::Tools::Vcf::CreateCrossSampleVcf->create(
            forced_variations_build_id => $self->forced_variations_build_id,
            builds => \@builds,
            output_directory => $staging_directory,
            max_files_per_merge => $self->max_files_per_merge,
            variant_type => $self->variant_type,
            roi_list => $self->roi_list,
            wingspan => $self->wingspan,
            allow_multiple_processing_profiles => $self->allow_multiple_processing_profiles,
            joinx_version => $self->joinx_version,
    );
    my $return_value = $cmd->generate_result();
    Carp::croak($self->error_message('Command failed')) unless $return_value;
}

1;
