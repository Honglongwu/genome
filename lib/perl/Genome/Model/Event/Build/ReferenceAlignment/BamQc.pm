package Genome::Model::Event::Build::ReferenceAlignment::BamQc;

use strict;
use warnings;

use Genome;

class Genome::Model::Event::Build::ReferenceAlignment::BamQc {
    is  => ['Genome::Model::Event'],
    has_transient_optional => [
        _alignment_result => {is => 'Genome::SoftwareResult'}
    ],
    doc => 'runs BamQc on the bam(s) produced in the alignment step',
};

sub bsub_rusage {
    return '-q long';
}

sub shortcut {
    my $self = shift;

    my %params = $self->params_for_result;
    my $result = Genome::InstrumentData::AlignmentResult::Merged::BamQc->get_with_lock(%params);

    if ($result) {
        $self->status_message('Using existing result ' . $result->__display_name__);
        return $self->link_result($result);  #add user and symlink dir to alignment result output dir
    } 
    else {
        return;
    }
}

sub execute {
    my $self  = shift;
    my $build = $self->build;
    my $pp    = $build->processing_profile;

    #Skip for bwamem and bwasw for now until all qc tools work
    if ($pp->read_aligner_name =~ /^bwa(mem|sw)$/i) {
        $self->warning_message('For now, skip BamQc step for bwamem and bwasw alignment bam');
        return 1;
    }

    my %params = (
        $self->params_for_result,
        log_directory => $build->log_directory,
    );

    my $result = Genome::InstrumentData::AlignmentResult::Merged::BamQc->get_or_create(%params);
    $self->link_result($result);

    return 1;
}

sub params_for_result {
    my $self  = shift;
    my $build = $self->build;
    my $pp    = $build->processing_profile;

    unless ($self->_alignment_result) {
        my $instrument_data_input = $self->instrument_data_input;
        my ($align_result) = $build->alignment_results_for_instrument_data($instrument_data_input->value);

        unless ($align_result) {
            die $self->error_message('No alignment result found for build: '. $build->id);
        }
        $self->_alignment_result($align_result);
    }

    my $picard_version = $pp->picard_version;

    if ($picard_version < 1.40) {
        my $pp_picard_version = $picard_version;
        $picard_version = Genome::Model::Tools::Picard->default_picard_version;
        $self->warning_message('Given picard version: '.$pp_picard_version.' not compatible to CollectMultipleMetrics. Use default: '.$picard_version);
    }

    my $instr_data  = $self->instrument_data;
    my $er_pileup   = $pp->read_aligner_name =~ /^bwa$/i ? 0 : 1;
    my $read_length = $instr_data->sequencing_platform =~ /^solexa$/i ? 0 : 1;

    return (
        alignment_result_id => $self->_alignment_result->id,
        picard_version      => $picard_version,
        samtools_version    => $pp->samtools_version,
        fastqc_version      => '0.10.0',
        samstat_version     => Genome::Model::Tools::SamStat::Base->default_samstat_version,
        error_rate          => 1,
        error_rate_pileup   => $er_pileup,
        read_length         => $read_length,
        test_name           => $ENV{GENOME_SOFTWARE_RESULT_TEST_NAME} || undef,
    );
}

sub link_result {
    my ($self, $result) = @_;

    my $build = $self->build;
    $result->add_user(label => 'uses', user => $build);

    my $align_result = $self->_alignment_result;
    my $link = join('/', $align_result->output_dir, 'bam-qc-'.$result->id);

    if (-l $link) {
        $self->status_message("Already found a symlink here.");
    }
    else {
        Genome::Sys->create_symlink($result->output_dir, $link);
        $align_result->_reallocate_disk_allocation;
    }

    my @users = $align_result->users;
    unless (grep{$_->user eq $result}@users) {
        $align_result->add_user(label => 'uses', user => $result);
    }

    return 1;
}

1;
