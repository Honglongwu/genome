package Genome::InstrumentData::Command::Import::WorkFlow::FastqsToBam;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
require File::Basename;
require List::Util;

class Genome::InstrumentData::Command::Import::WorkFlow::FastqsToBam { 
    is => 'Command::V2',
    has_input => [
        working_directory => {
            is => 'Text',
            doc => 'Destination directory for fastqs.',
        },
        fastq_paths => { 
            is => 'Text',
            is_many => 1,
            doc => 'Paths of the fastq[s] to convert to a bam.',
        },
        library => {
            is => 'Genome::Library',
            doc => 'The library name to use and then derive the read group name.',
        },
    ],
    has_output => [ 
        output_bam_path => {
            is => 'Text',
            calculate_from => [qw/ working_directory sample_name /],
            calculate => q( return $working_directory.'/'.$sample_name.'.bam'; ),
            doc => 'The path of the bam.',
        },
    ],
    has_calculated => {
        sample_name => {
            calculate_from => [qw/ library /],
            calculate => q( return $library->sample->name ),
        },
    },
};

sub execute {
    my $self = shift;
    $self->debug_message('Fastqs to bam...');

    my $fastq_to_bam_ok = $self->_fastqs_to_bam;
    return if not $fastq_to_bam_ok;

    my $verify_bam_ok = $self->_verify_bam;
    return if not $verify_bam_ok;

    my $cleanup_ok = Genome::InstrumentData::Command::Import::WorkFlow::Helpers->remove_paths_and_auxiliary_files($self->fastq_paths);
    return if not $cleanup_ok;

    $self->debug_message('Fastqs to bam...done');
    return 1;
}

sub _fastqs_to_bam {
    my $self = shift;
    $self->debug_message('Run picard fastq to sam...');

    my $sample_name = $self->sample_name;
    my $read_group_name = $self->library->name;
    my @fastqs = $self->fastq_paths;
    $self->debug_message("Fastq 1: $fastqs[0]");
    my $output_bam_path = $self->output_bam_path;
    my $cmd = "gmt picard fastq-to-sam --fastq $fastqs[0] --output $output_bam_path --quality-format Standard --sample-name $sample_name --read-group-name $read_group_name";
    if ( $fastqs[1] ) {
        $self->debug_message("Fastq 2: $fastqs[1]") if $fastqs[1];
        $cmd .= ' --fastq2 '.$fastqs[1]
    }
    $self->debug_message("Bam path: $output_bam_path");

    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
    if ( not $rv or not -s $output_bam_path ) {
        $self->error_message($@) if $@;
        $self->error_message('Failed to run picard fastq to sam!');
        return;
    }

    $self->debug_message('Run picard fastq to sam...done');
    return 1;
}

sub _verify_bam {
    my $self = shift;
    $self->debug_message('Verify bam...');

    my $helpers = Genome::InstrumentData::Command::Import::WorkFlow::Helpers->get;

    my $flagstat = $helpers->validate_bam($self->output_bam_path);
    return if not $flagstat;

    $self->debug_message('Bam read count: '.$flagstat->{total_reads});

    $self->debug_message('Verify bam...done');
    return 1;
}

1;

