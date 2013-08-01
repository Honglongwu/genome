package Genome::InstrumentData::AlignedBamResult;

use Genome;

use warnings;
use strict;

class Genome::InstrumentData::AlignedBamResult {
    is => 'Genome::SoftwareResult::Stageable',
    is_abstract => 1,
    attributes_have => [
        is_output => { is => 'Boolean', is_optional => 1, },
    ],
    has_input => [
        reference_build => { # PROVIDES fasta VIA full_consensus_path('fa')
            is => 'Genome::Model::Build::ImportedReferenceSequence',
        },
    ],
    has_constant => [
        # from inputs
        reference_fasta => { 
            calculate_from => [qw/ reference_build /],
            calculate => q| return $reference_build->full_consensus_path('fa'); |, 
        },
        # from output
        bam_path => { # this is called bam_file in merged
            is_output => 1,
            calculate => q| return $self->output_dir.'/'.$self->id.'.bam'; |, 
        },
        bam_file => { # alias
          is => 'Text',
          via => '__self__',
          to => 'bam_path',
        },
        # flagstat
        bam_flagstat_path => {
            calculate_from => [qw/ bam_path /],
            calculate => q| return $bam_path.'.flagstat'; |,
        },
        bam_flagstat_file => { # alias
          is => 'Text',
          via => '__self__',
          to => 'bam_flagstat_path',
        },
    ],
};

sub run_flagstat_on_output_bam_path {
    my $self = shift;
    $self->status_message('Run flagstat on output bam file...');

    my $bam_path = $self->bam_path;
    if ( not $bam_path or not -s $bam_path ) {
        $self->error_message('Bam file not set or does not exist!');
        return;
    }

    my $flagstat_path = $self->bam_flagstat_path;
    $self->status_message("Flagstat file: $flagstat_path");
    my $cmd = "samtools flagstat $bam_path > $flagstat_path";
    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
    if ( not $rv or not -s $flagstat_path ) {
        $self->error_message($@) if $@;
        $self->error_message('Failed to run flagstat!');
        return;
    }
    my $flagstat = Genome::Model::Tools::Sam::Flagstat->parse_file_into_hashref($flagstat_path);
    $self->status_message('Flagstat output:');
    $self->status_message( join("\n", map { ' '.$_.': '.$flagstat->{$_} } sort keys %$flagstat) );
    if ( not $flagstat->{total_reads} > 0 ) {
        $self->error_message('Flagstat determined that there are no reads in bam! '.$bam_path);
        return;
    }

    $self->status_message('Run flagstat on output bam file...done');
    return $flagstat;
}

1;

