package Genome::Model::Tools::Sx::Trim::Flexbar;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Sx::Trim::Flexbar {
    is => 'Genome::Model::Tools::Sx::ExternalCmdBase',
    has => [
        __PACKAGE__->_cmd_properties,
        adapter => {
            is => 'Text',
            is_optional => 1,
            doc => 'Adaptor sequence to be removed.',
        },
        remove_revcomp => {
            is => 'Boolean',
            is_optional => 1,
            default => 0,
            doc => 'Remove the reverse compl;ement of the single adapter.',
        },
        version => {
            is => 'Text',
            valid_values => [ __PACKAGE__->cmd_versions ],
            doc => 'Verion of flexbar to use.',
        },
        _tmp_flexbar_inputs => { is => 'Array', is_optional => 1, },
    ],
};

sub help_brief {
    return 'Trim with the [flex]ible [bar]code detection and adapter removal';
}

sub cmd_display_name {
    return 'flexbar';
}

sub _cmd_versions {
    return (
        '229' => '/usr/bin/flexbar229',
    );
}

sub cmd_versions {
    my $self = shift;
    my %versions = $self->_cmd_versions;
    return sort keys %versions;
}

sub _cmd_properties {
    # Removed algorithm, cut_off
    return (
        adapters => {
            is => 'Text',
            is_optional => 1,
            doc => 'Fasta file of adapter sequences to be removed.',
        },
        adapter_min_overlap => {
            is => 'Text',
            is_optional => 1,
            doc => ' Minimum overlap of adapter and read in base pairs.',
        },
         adapter_threshold  => {
             is => 'Number',
             is_optional => 1,
             doc => 'Allowed mismatches and indels per 10 bases for adapter',
         },
         adapter_trim_end => {
             is => 'Text',
             valid_values => [qw/ ANY RIGHT LEFT RIGHT_TAIL LEFT_TAIL  /],
             doc => 'Decides on which end adapter removal is performed.',
         },
         adapter_tail_length => {
             is => 'Number',
             is_optional => 1,
             doc => ' Number of bases for tail trim-end types, default: adapter length',
         },
         adapter_no_adapt => {
             is => 'Boolean',
             is_optional => 1,
             doc => 'Do not adapt min-overlap to overlap length at ends.',
         },
         adapter_match => {
             is => 'Number',
             is_optional => 1,
             doc => 'Match score.',
         },
         adapter_mismatch => {
             is => 'Number',
             is_optional => 1,
             doc => 'Mismatch score.',
         },
         adapter_gap_cost => {
             is => 'Number',
             is_optional => 1,
             doc => 'Gap score.',
         },
         min_readlength => {
             is => 'Text',
             is_optional => 1,
             doc => 'Minimum readlength in basepairs after adapter removal or read will be discarded.',
         },
         max_uncalled => {
             is => 'Text',
             is_optional => 1,
             doc => 'Number of allowed uncalled bases in a read.',
         },
         no_length_dist => {
             is => 'Boolean',
             is_optional => 1,
             default_value => '1',
             doc => 'Prevent writing length distributions for read output files.',
         },
         removal_tag => {
             is => 'Boolean',
             is_optional => 1,
             doc => 'Tag reads for which adapter or barcode is removed.',
         },
         threads => {
             is => 'Text',
             is_optional => 1,
             default_value => 1,
             doc => 'Number of threads to use.',
         },
     );
 }

 sub execute {
     my $self = shift;

     my $resolve_adapters = $self->_resolve_adapters;
     return if not $resolve_adapters;

     my @input_params = $self->_resolve_input_params;
     return if not @input_params;

     my $output = $self->_init_ouptut;
     return if not $output;

     $self->status_message('Run flexbar...');
     my $cmd = $self->build_command;
    $cmd .= ' --source '.$input_params[0]->{file};
    $cmd .= ' --source2 '.$input_params[1]->{file} if $input_params[1];
    $cmd .= ' --format fastq-sanger';
    $cmd .= ' --target '.$self->_tmpdir.'/output.fastq',
    my $rv = $self->_run_command($cmd);
    return if not $rv;
    $self->status_message('Run flexbar...OK');

    my @fastq_files = glob $self->_tmpdir.'/output*.fastq';
    my @outputs = grep { $_ !~ /single/ } @fastq_files;
    if ( not @outputs ) {
        $self->error_message('Failed to find output files! Files in output directory: ');
        return;
    }
    $self->status_message('Output: '.join(' ', @outputs));
    
    my $output_reader = Genome::Model::Tools::Sx::Reader->create(
        config => [ map { $_.':type=sanger' } @outputs ],
    );
    if ( not $output_reader ) {
        $self->error_message('Failed to open reader for flexbar output!');
        return;
    }

    $self->status_message('Processing flexbar output...');
    while ( my $seqs = $output_reader->read ) {
        $output->write($seqs);
    }

    $self->_rm_tmpdir;

    return 1;
}

sub _resolve_adapters {
    my $self = shift;

    if ( $self->adapters and $self->adapter ) {
        $self->error_message('Cannot specify both adpaters file (adapters) and single adapter (adapter) params!');
        return;
    }

    if ( $self->adapters ) { # using adapters file
        $self->error_message('Cannot specify both adpaters file (adapters) and single adapter (adapter) params!') if $self->adapter;
        $self->error_message('Cannot specify to remove reverse complement adapter (remove_revcomp) and adpaters file (adapters) params!') if $self->remove_revcomp;
        return 1 if -s $self->adapters;
        $self->error_message('Adapters file does not exist! '.$self->adapters);
        return;
    }

    my $adapters_file = $self->_tmpdir.'/adapters.fasta';
    $self->adapters($adapters_file);
    my $writer = Genome::Model::Tools::Sx::PhredWriter->create(file => $adapters_file);
    if ( not $writer ) {
        $self->error_message('Failed to create fasta writer!');
        return;
    }

    my $adapter = uc($self->adapter);
    $writer->write({ id => 'Adapter', seq => $adapter, });
    if ( $self->remove_revcomp ) {
        my $revcomp_adapter = reverse $adapter;
        $revcomp_adapter =~ tr/TCGA/AGCT/;
        $writer->write({ id => 'Adapter-Rev-Complement', seq => uc( $revcomp_adapter ), });
    }

    return 1;
}

sub _required_type_and_counts_for_inputs {
    return ( 'sanger', [qw/ 1 2 /], );
}

1;

