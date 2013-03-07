package Genome::Model::MetagenomicComposition16s;

use strict;
use warnings;

use Genome;

class Genome::Model::MetagenomicComposition16s {
    is => 'Genome::ModelDeprecated',
    has_param => [
        amplicon_processor => {
            is => 'Text',
            is_optional => 1,
            doc => 'A string of paramters to process amplicons by',
        },
        assembler => {
            is => 'Text',
            is_optional => 1,
            doc => 'Assembler name for assembling the reads.',
            valid_values => [qw/ phred_phrap /],
        },
        assembler_params => {
            is => 'Text',
            is_optional => 1,
            doc => 'A string of parameters to pass to the assembler',
        },
        classifier => {
            is => 'Text',
            is_optional => 1,
            doc => 'Classifier name for classifing the amplicons.',
            valid_values => [qw/ rdp2-1 rdp2-2 rdp2-3 rdp2-5 /],
        },
        classifier_params => {
            is => 'Text',
            is_optional => 1,
            doc => 'A string of parameters to pass to the classifier.',
        },
        chimera_detector => {
            is => 'Text',
            is_optional => 1,
            doc => 'Chimera detector name, chimera slayer or nastier'
        },
        chimera_detector_params => {
            is => 'Text',
            is_optional => 1,
            doc => 'A string of parameters to pass to chimera detector',
        },
    ],
};

sub sequencing_platform {
    my $self = shift;
    my @instrument_data = $self->instrument_data;
    return if not @instrument_data;
    my %sequencing_platforms = map { $_->sequencing_platform => 1 } @instrument_data;
    # TODO error for multiple?
    return (keys %sequencing_platforms)[0];
}

#< Processing Profile >#
sub default_processing_profile_ids {
    # RT66900 from 2278045 to 2571784 
    # RT85266 add 2752939
    return ( 
        '2571784',# RDP 2.2 set 6
        '2752939',# RDP 2.5 set 9
    );
}

sub default_processing_profile_id {
    # In addition to AQID, the run status command uses this. Please update it if this functionality is moved. -ebelter
    my @default_processing_profile_ids = default_processing_profile_ids();
    return $default_processing_profile_ids[0];
}

sub __profile_errors__ {
    my ($self, $pp) = @_;

    my @errors;
    for my $param_name (qw/ amplicon_processor chimera_detector /) {
        my $value = $pp->$param_name;
        my $params_method = $param_name.'_params';
        my $params = eval{ $pp->$params_method; };
        my $validate_method = 'validate_'.$param_name;
        my @error_msgs = $self->$validate_method($value, $params);
        next if not @error_msgs;
        for my $error_msg ( @error_msgs ) {
            $self->error_message($error_msg);
            push @errors, UR::Object::Tag->create(
                type => 'invalid',
                properties => [ $param_name ],
                desc => $error_msg,
            );
        }
    }

    return @errors;
}

sub validate_amplicon_processor {
    my ($self, $amplicon_processor) = @_;

    return if not $amplicon_processor;
    $self->status_message('Validate amplicon processor...');

    my @error_msgs;
    $self->status_message('Amplicon processor: '.$amplicon_processor);
    my @commands = split(/\|/, $amplicon_processor);
    for my $command ( @commands ) {
        $self->status_message('Validate part: '.$command);
        $command =~ s/^\s+//;
        $command =~ s/\s+$//;
        $command = "gmt sx $command";
        my $valid = Genome::Model::Tools::Sx::Validate->validate_command( $command );
        if ( not $valid ) {
            push @error_msgs, "Invalid amplicon processor command: $command";
        }
    }

    $self->status_message('Validate amplicon processor...DONE');
    return @error_msgs;
}

sub validate_chimera_detector {
    my ($self, $detector, $params) = @_;

    return if not $detector and not $params;
    $self->status_message('Validate chimera detector...');

    if ( not $detector or not $params ) {
        return ( 'Cannot give chimera detector without params or vice versa!' );
    }
    $detector =~ s/_/\-/g;

    my $class = 'Genome::Model::Tools::'.Genome::Utility::Text::string_to_camel_case(join(' ', split('-', $detector))).'::DetectChimeras';
    my $meta = eval{ $class->__meta__; };
    if ( not $meta ) {
        return ( "Invalid chimera detector: $detector" );
    }

    my $cmd = "gmt $detector detect-chimeras $params";
    $self->status_message('Chimera detector command: '.$cmd);
    $cmd .= ' -h 2>&1 > /dev/null'; # add help to check for invalid opts, redirect to dev/null

    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd, print_status_to_stderr => 0); };
    if ( not $rv ) {
        return 'Failed to validate chimera detector and params!';
    }

    $self->status_message('Validate chimera detector...DONE');
    return;
}

sub validate_classifier {
    my ($self, $classifier, $params) = @_;

    return if not $classifier and not $params;
    $self->status_message('Validate classifier...');

    if ( not $classifier or not $params ) {
        return ( 'Cannot give chimera detector without params or vice versa!' );
    }
    $classifier =~ s/_/\-/g;

    my $class = 'Genome::Model::Tools::MetagenomicClassifier'.Genome::Utility::Text::string_to_camel_case(join(' ', split('-', $classifier)));
    my $meta = eval{ $class->__meta__; };
    if ( not $meta ) {
        return ( "Invalid classifier detector: $classifier" );
    }

    my $cmd = "gmt metagenomic-classifier $classifier $params -h"; 
    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
    if ( not $rv ) {
        $self->error_message('Failed to execute classifier command');
        return;
    }

    $self->status_message('Validate classifier...DONE');
    return 1;
}
#<>#

sub build_subclass_name {
    return 'metagenomic-16s-composition';
}

sub _additional_parts_for_default_name {
    my $self = shift;

    my @parts;
    my $subject = $self->subject;
    if ( $subject->isa('Genome::Sample') and defined $subject->tissue_desc ) {
        push @parts, $subject->tissue_desc;
    }

    push @parts, $self->processing_profile->classifier;

    return @parts;
}

sub is_for_qc {
    my $self = shift;
    return 1 if $self->name =~ /\-qc$/;
    return 0;
}

1;

