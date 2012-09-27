package Genome::Model::Tools::Sx::ExternalCmdBase;

use strict;
use warnings;

use Genome;

require Cwd;
use Switch;

class Genome::Model::Tools::Sx::ExternalCmdBase {
    is => 'Genome::Model::Tools::Sx::Base',
    is_abstract => 1,
    has => [
        _cmds => {
            is => 'Array',
            is_optional => 1,
            is_transient => 1,
            default_value => [],
            doc => 'Commands that were run.',
        },
    ],
};

sub cmd_display_name {
    Carp::confess('Please implement cmd_display_name in '.$_[0]->class);
}

sub _tmpdir {
    my $self = shift;
    $self->{_tmpdir} = Genome::Sys->create_temp_directory if not $self->{_tmpdir};
    return $self->{_tmpdir};
}

sub _rm_tmpdir {
    my $self = shift;
    return 1 if not $self->{_tmpdir};
    return File::Path::rmtree( $self->{_tmpdir} );
}

sub executable_path {
    my $self = shift;

    if ( not $self->version ) {
        $self->error_message('No version to get executable path!');
        return;
    }

    my %versions = $self->_cmd_versions;
    if ( not $versions{ $self->version } ) {
        $self->error_message('Invalid version! '.$self->version);
        return;
    }

    return $versions{ $self->version };
}

sub cmd_property_names {
    my $self = shift;
    my %cmd_properties = eval{ $self->_cmd_properties; };
    return sort keys %cmd_properties;
}

sub build_command {
    my $self = shift;

    my $cmd = $self->executable_path;
    return if not $cmd;

    my $meta = $self->__meta__;
    my @cmd_property_names = $self->cmd_property_names;
    for my $key ( @cmd_property_names ) {
        my $property = $meta->property_meta_for_name($key);
        my $value = $self->$key;
        next if not defined $value;
        $key =~ s/\_/\-/g;
        $cmd .= sprintf(
            ' %s%s%s',
            ( length($key) == 1 ? '-' : '--'),                       # - or --
            $key,                                                    # param name
            ( $property->data_type eq 'Boolean' ? '' : ' '.$value ), # value or empty string for boolean
        );
    }

    return $cmd;
}

sub _run_command {
    my ($self, $cmd) = @_;

    my $cmds = $self->_cmds;
    push @$cmds, $cmd;
    $self->_cmds($cmds);

    my $cwd = Cwd::getcwd();
    chdir $self->_tmpdir;

    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
    chdir $cwd;

    if ( not $rv ) {
        $self->error_message($@) if $@;
        $self->error_message("Failed to run: $cmd");
        return;
    }

    return 1;
}

sub _resolve_cmd_input_configs {
    my $self = shift;

    my $cmd_display_name = $self->cmd_display_name;
    $self->status_message("Check if inputs for $cmd_display_name need to be written...");
    my ($required_type, $required_counts) = $self->_required_type_and_counts_for_inputs;
    my @input_configs = $self->input;
    my @input_params;
    for my $input_config ( @input_configs ) {
        my ($class, $params) = Genome::Model::Tools::Sx::Reader->parse_reader_config($input_config);
        last if $class->type ne $required_type;
        push @input_params, $params;
    }

    # The input files that are valid must be all the input configs plus match the allowable counts
    if ( @input_configs == @input_params ) {
        if ( not @$required_counts or grep { @input_params == $_ } @$required_counts ) {
            $self->status_message('Using original inputs!');
            return @input_params;
        }
    }

    $self->status_message("Must write $cmd_display_name input files...");
    my $input = $self->_init_input;
    return if not $input;

    my $seqs = $input->read;
    my $cnt = @$seqs; 
    $self->status_message('Input count: '.$cnt);

    my $format;
    switch ($required_type) {
        case 'phred'    { $format = 'fasta' }
        case 'sanger'   { $format = 'fastq' }
        case 'illumina' { $format = 'fastq' }
        else            { $format = $required_type }
    }

    my @writer_config = ( 'file='.$self->_tmpdir."/input_1.$format:type=$required_type" );
    $writer_config[0] .= ':qual_file='.$self->_tmpdir."/input_1.qual" if $required_type eq 'phred'; # FIXME this will not always work

    if ( $cnt == 2 ) { # assume paired
        $writer_config[0] .= ':name=fwd';
        push @writer_config, $self->_tmpdir."/input_2.$format:type=$required_type:name=rev";
        $writer_config[1] .= ':qual_file='.$self->_tmpdir."/input_1.qual" if $required_type eq 'phred'; # FIXME this will not always work
        $self->status_message('Writing input as paired');
    }

    my $input_writer = Genome::Model::Tools::Sx::Writer->create(
        config => \@writer_config,
    );
    if ( not $input_writer ) {
        $self->error_message('Failed to open input writer!');
        return;
    }
    do {
        $input_writer->write($seqs);
    } while $seqs = $input->read;
    $self->status_message('Write input...OK');

    @input_params = ();
    for my $config ( @writer_config ) {
        my ($class, $params) = Genome::Model::Tools::Sx::Writer->parse_writer_config($config);
        push @input_params, $params;
    }

    return @input_params;
}

1;

