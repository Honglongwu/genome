package Genome::InstrumentData::Gatk::Base;

use strict;
use warnings;

use Genome;

class Genome::InstrumentData::Gatk::Base {
    is => 'Genome::InstrumentData::AlignedBamResult',
    has_input => [
        bam_source => { # PROVIDES bam_path SHOULD be in aligned bam result, but would be incompatible with AR::Merged
            is => 'Genome::InstrumentData::AlignedBamResult',
        },
    ],
    has_param => [
        version => {
            is => 'Text',
            doc => 'Version of GATK to use.',
            valid_values => [qw/ 2.4 /],
        },
    ],
    has_constant => [
        _tmpdir => {  calculate => q| return File::Temp::tempdir(CLEANUP => 1); |, },
        # from inputs
        input_bam_path => { 
            via => 'bam_source',
            to => 'bam_path', 
        },
    ],
};

sub resolve_allocation_subdirectory {
    my $self = shift;
    my $class = $self->class;
    $class =~ s/^Genome::InstrumentData::Gatk:://;
    $class =~ s/Result$//;
    return sprintf(
        "model_data/gatk/%s-%s-%s-%s-%s", 
        Genome::Utility::Text::camel_case_to_string($class, '_'), 
        Sys::Hostname::hostname(),
        $ENV{USER}, $$, $self->id,
    );
}

sub resolve_allocation_kilobytes_requested {
    my $self = shift;
    my $kb_requested = -s $self->input_bam_path;
    return int($kb_requested / 1024 * 1.5);
}

sub resolve_allocation_disk_group_name {
    return 'info_genome_models';
}

sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    return if not $self;

    my $prepare_output_directory = eval{ $self->_prepare_output_directory; };
    if ( not $prepare_output_directory ) {
        $self->error_message($@) if $@;
        $self->error_message('Failed to prepare output directory!') if $@;
        return;
    }

    return $self;
}

1;

