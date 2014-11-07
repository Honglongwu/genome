package Genome::VariantReporting::Framework::GenerateReport;

use strict;
use warnings;
use Genome;
use Genome::File::Vcf::Reader;
use Memoize;

class Genome::VariantReporting::Framework::GenerateReport {
    is => 'Command::V2',
    has_input => [
        input_vcf => {
            is => 'File',
        },
        plan_json => {
            is => 'Text',
        },
        output_directory => {
            is => 'Path',
            is_output => 1,
        },
        variant_type => {
            is => 'Text',
            valid_values => ['snvs', 'indels'],
        },
        provider_json => {
            is => 'Text',
        },
    ],
    has_param => [
        lsf_resource => {
            value => q{-R 'select[mem>16000] rusage[mem=16000]' -M 16000000},
        },
    ],
};

sub plan {
    my $self = shift;

    return Genome::VariantReporting::Framework::Plan::MasterPlan->create_from_json($self->plan_json);
}
Memoize::memoize('plan');

sub translations {
    my $self = shift;
    my $provider = Genome::VariantReporting::Framework::Component::RuntimeTranslations->create_from_json($self->provider_json);

    return $provider->translations;
}
Memoize::memoize('translations');

sub execute {
    my $self = shift;

    $self->status_message("Reading from: ".$self->input_vcf."\n");

    my @reporters = $self->create_reporters;
    $self->initialize_reporters(@reporters);

    my $vcf_reader = Genome::File::Vcf::Reader->new($self->input_vcf);
    while (my $entry = $vcf_reader->next) {
        for my $reporter (@reporters) {
            $reporter->process_entry($entry);
        }
    }

    $self->finalize_reporters(@reporters);
    return 1;
}

sub create_reporters {
    my $self = shift;

    my @reporters;
    for my $reporter_plan ($self->plan->reporter_plans) {
        push @reporters, $reporter_plan->object($self->translations);
    }

    return @reporters;
}

sub initialize_reporters {
    my $self = shift;
    map {$_->initialize($self->output_directory)} @_;
    return;
}

sub finalize_reporters {
    my $self = shift;
    map {$_->finalize()} @_;
    return;
}

1;
