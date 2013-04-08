package Genome::InstrumentData::Command::Import::Basic;

use strict;
use warnings;

use Genome;

class Genome::InstrumentData::Command::Import::Basic { 
    is => 'Command::V2',
    has => [
        import_source_name => {
            is => 'Text',
            doc => 'Organiztion name or abbreviation from where the source file(s) were generated or downloaded.',
        },
        source_files => {
            is => 'Text',
            is_many => 1,
            doc => 'Source files to import. If importing multiple files, put the file containing the forward reads first.',
        },
        sample => {
            is => 'Genome::Sample',
            doc => 'Sample to use. The external library for the instrument data will be gotten or created.',
        },
    ],
    has_optional => [
        description  => {
            is => 'Text',
            doc => 'Description of the data.',
        },
        instrument_data_properties => {
            is => 'Text',
            is_many => 1,
            doc => 'Name and value pairs to add to the instrument data. Separate name and value with an equals (=) and name/value pairs with a comma (,).',
        },
    ],
    has_transient_optional => [
        library => { is => 'Genome::Library', },
        instrument_data => { is => 'Genome::InstrumentData', },
        original_format => { is => 'Text', },
        import_format => { is => 'Text', },
        is_paired_end => { is => 'Boolean', },
        kilobytes_requested => { is => 'Number', },
        final_data_file => { is => 'Text', },
        read_count  => { is => 'Number', }, # calculated
        _tmp_dir => { is => 'Text', },
        _data_file => { is => 'Text', },
    ],
    has_constant => [
        sequencing_platform => { is => 'Text', value => 'solexa', },
    ],
    has_calculated_optional => [
        file_attribute_label => {
            calculate_from => 'import_format',
            calculate => sub{
                my ($import_format) = @_;
                my %formats_to_labels = (
                    'bam' => 'bam_path',
                    'sanger fastq' => 'archive_path',
                );
                Carp::confess('Unsupported format! '.$import_format) if not $formats_to_labels{$import_format};
                return $formats_to_labels{$import_format};
            },
        },
    ],
};

sub help_detail {
    return 'Import intrument data. Can be in the format of fastqs [gzipped ok] or bam. Format is guessed from file suffix. Recognized suffixes include fastq, fq, txt and bam. Files will be transferred and correctly named. Read count and paired endness will also be determined.';
}

sub execute {
    my $self = shift;
    $self->status_message('Import instrument data...');

    my $library = $self->_resvolve_library;
    return if not $library;

    my $validate_source_files = $self->_validate_source_files;
    return if not $validate_source_files;

    my $instrument_data = $self->_create_instrument_data;
    return if not $instrument_data;

    my $transfer_ok = $self->_transfer_source_files;
    return if not $transfer_ok;

    my $finish_ok = $self->_finish;
    return if not $finish_ok;

    $self->status_message('Import instrument data...done');
    return 1;
}

#< Library >#
sub _resvolve_library {
    my $self = shift;
    $self->status_message('Resolve library...');

    my $sample = $self->sample;
    $self->status_message('Sample name: '.$sample->name);
    $self->status_message('Sample id: '.$sample->id);
    my $library_name = $sample->name.'-extlibs';
    $self->status_message('Library name: '.$library_name);
    my $library = Genome::Library->get(
        name => $library_name,
        sample => $sample,
    );
    if ( not $library ) {
        $library = Genome::Library->create(
            name => $library_name,
            sample => $sample,
        );
        if ( not $library ) {
            $self->error_message('Failed to get or create external library for sample! '.$sample->id);
            return;
        }
    }
    $self->status_message('Library id: '.$library->id);

    $self->status_message('Resolve library...done');
    return $self->library($library);
}
#<>#

#< Validate Source Files >#
sub _validate_source_files {
    my $self = shift;
    $self->status_message('Validate source files...');

    my @source_files = $self->source_files;
    for my $source_file ( @source_files ) { $self->status_message("Source file(s): $source_file"); }
    $self->status_message("Source file count: ".@source_files);

    my $resolve_formats_ok = $self->_resolve_start_and_import_format(@source_files);
    return if not $resolve_formats_ok;

    my $max_source_files = ( $self->original_format =~ /fast[aq]/ ? 2 : 1 );
    if ( @source_files > $max_source_files ) {
        $self->error_message("Cannot handle more than $max_source_files source files!");
        return;
    }

    my $kilobytes_requested = $self->_resolve_kilobytes_requested(@source_files);
    return if not $kilobytes_requested;
    $kilobytes_requested += 51_200; # a little extra
    $self->kilobytes_requested($kilobytes_requested);
    $self->status_message('Kilobytes requested: '.$self->kilobytes_requested);

    $self->status_message('Validate source files...done');
    return 1;
}

sub _resolve_start_and_import_format {
    my ($self, @source_files) = @_;
    $self->status_message('Resolve start and import format...');

    my %suffixes;
    for my $source_file ( @source_files ) {
        $source_file =~ s/\.gz$//;
        my ($suffix) = $source_file =~ /\.(\w+)$/;
        if ( not $suffix ) {
            $self->error_message("Failed to get suffix from source file! $source_file");
            return;
        }
        $suffixes{$suffix}++;
    }

    my %suffixes_to_original_format = (
        txt => 'fastq',
        fastq => 'fastq',
        fq => 'fastq',
        #fasta => 'fasta',
        bam => 'bam',
        sra => 'sra',
    );
    my %formats;
    for my $suffix ( keys %suffixes ) {
        if ( not exists $suffixes_to_original_format{$suffix} ) {
            $self->error_message('Unrecognized suffix! '.$suffix);
            return;
        }
        $formats{ $suffixes_to_original_format{$suffix} } = 1;
    }

    my @formats = keys %formats;
    if ( @formats > 1 ) {
        $self->error_message('Got more than one format when trying to determine format!');
        return;
    }
    my $original_format = $formats[0];
    $self->original_format($original_format);
    $self->status_message('Start format: '.$self->original_format);

    my %original_format_to_import_format = ( # temp, as everything will soon be bam
        fastq => 'sanger fastq',
        #fastq => 'bam',
        bam => 'bam',
        sra => 'bam',
    );
    $self->import_format( $original_format_to_import_format{$original_format} );
    $self->status_message('Import format: '.$self->import_format);

    $self->status_message('Resolve start and import format...done');
    return 1;
}

sub _resolve_kilobytes_requested {
    my ($self, @source_files) = @_;

    my $kilobytes_requested;
    for my $source_file ( @source_files ) {
        my $size = -s $source_file;
        if ( not $size ) {
            $self->error_message("Source file does not exist! $source_file");
            return;
        }
        $size = int( $size / 1024 );
        $size *= 3 if $source_file =~ /\.gz$/; # assume ~30% compression rate for gzipped fasta/q
        $kilobytes_requested += $size;
    }
    $kilobytes_requested *= 2 if $self->original_format =~ /fast[aq]/;# extra for tar file
    $kilobytes_requested *= 3 if $self->original_format =~ /bam/;# extra for sorting

    return $kilobytes_requested;
}
#<>#

#< Create Inst Data >#
sub _create_instrument_data {
    my $self = shift;

    $self->status_message('Checking if source files were previously imported...');
    my %properties = (
        library => $self->library,
        original_data_path => join(',',  $self->source_files),
    );
    my $instrument_data = Genome::InstrumentData::Imported->get(%properties);
    if ( $instrument_data ) {
        $self->error_message('Found existing instrument data for library and source files. Were these previously imported? Exiting instrument data id: '.$instrument_data->id.', source files: '.$properties{original_data_path});
        return;
    }
    $self->status_message('Source files were NOT previously imported!');

    $self->status_message('Create instrument data...');
    $properties{import_format} = $self->import_format;# will soon be 'bam'
    $properties{sequencing_platform} = $self->sequencing_platform;
    $properties{import_source_name} = $self->import_source_name;
    $properties{description} = $self->description;
    for my $name_value ( $self->instrument_data_properties ) {
        my ($name, $value) = split('=', $name_value);
        if ( not defined $value or $value eq '' ) {
            $self->error_message('Failed to parse with instrument data property name/value! '.$name_value);
            return;
        }
        if ( exists $properties{$name} and $value ne $properties{$name} ) {
            $self->error_message(
                "Multiple values for instrument data property! $name => ".join(', ', sort $value, $properties{$name})
            );
            return;
        }
        $properties{$name} = $value;
    }

    $instrument_data = Genome::InstrumentData::Imported->create(%properties);
    if ( not $instrument_data ) {
        $self->error_message('Failed to create instrument data!');
        return;
    }
    $self->status_message('Instrument data id: '.$instrument_data->id);

    my $allocation = Genome::Disk::Allocation->create(
        disk_group_name => 'info_alignments',
        allocation_path => 'instrument_data/imported/'.$instrument_data->id,
        kilobytes_requested => $self->kilobytes_requested,
        owner_class_name => $instrument_data->class,
        owner_id => $instrument_data->id,
    );
    if ( not $allocation ) {
        $self->error_message('Failed to create allocation for instrument data! '.$instrument_data->id);
        return;
    }
    $self->status_message('Allocation id: '.$allocation->id);
    $self->status_message('Allocation path: '.$allocation->absolute_path);

    my $tmp_dir = $allocation->absolute_path.'/tmp';
    Genome::Sys->create_directory($tmp_dir);
    $self->_tmp_dir($tmp_dir);
    $self->status_message('Allocation tmp path: '.$tmp_dir);

    $self->status_message('Create instrument data...done');
    return $self->instrument_data($instrument_data);
}

#<TransferSourceFiles>#
sub _transfer_source_files {
    my $self = shift;
    my $original_format = $self->original_format;
    if ( $original_format eq 'fastq' ) {
        return $self->_transfer_fastq_source_files;
    }
    elsif ( $original_format eq 'bam' ) {
        return $self->_transfer_bam_source_file;
    }
    elsif ( $original_format eq 'sra' ) {
        return $self->_transfer_sra_source_file;
    }
    else {
        Carp::confess("Unsupported start format! $original_format");
    }
}
#<>#

#<TransferBam>#
sub _transfer_bam_source_file {
    # TODO add md5
    my $self = shift;
    $self->status_message('Transfer bam file and run flagstat...');

    $self->status_message('Sort and copy...');
    my ($source_file) = $self->source_files;
    my $bam_base_name = 'all_sequences.bam';
    my $tmp_bam_file_prefix = $self->_tmp_dir.'/all_sequences';
    my $tmp_bam_file = $tmp_bam_file_prefix.'.bam';
    $self->status_message("Source file: $source_file");
    $self->status_message("Temp bam file: $tmp_bam_file");
    my $cmd = "samtools sort -m 3000000000 -n $source_file $tmp_bam_file_prefix";
    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
    if ( not $rv or not -s $tmp_bam_file ) {
        $self->error_message($@) if $@;
        $self->error_message('Failed to run samtools sort and copy to to temp bam!');
        return;
    }
    $self->status_message('Sort and copy...done');

    my $bam_file = $self->instrument_data->allocation->absolute_path.'/'.$bam_base_name;
    my $flagstat_file = $bam_file.'.flagstat';
    my $flagstat = $self->_verify_and_move_bam($tmp_bam_file, $bam_file);
    return if not $flagstat;

    $self->read_count($flagstat->{total_reads});
    $self->is_paired_end($flagstat->{is_paired_end});
    $self->final_data_file($bam_file);

    $self->status_message('Transfer bam file and run flagstat...done');
    return 1;
}

sub _verify_and_move_bam {
    my ($self, $bam_file, $new_bam_file) = @_;
    $self->status_message('Verify and move bam to permanent location...');

    my $flagstat_file = $new_bam_file.'.flagstat';
    my $flagstat = $self->_run_flagstat($bam_file, $flagstat_file);
    return if not $flagstat;
    $self->read_count($flagstat->{total_reads});
    $self->is_paired_end($flagstat->{is_paired_end});

    $self->status_message('Move bam file to permenant location...');
    $self->status_message("Permanent bam file: $new_bam_file");
    my $move_ok = File::Copy::move($bam_file, $new_bam_file);
    if ( not $move_ok ) {
        $self->error_message('Failed to move the tmp bam file!');
        return;
    }
    if ( not -s $new_bam_file ) {
        $self->error_message('Move of the tmp bam file succeeded, but bam file does not exist!');
        return;
    }

    $self->status_message('Verify and move bam to permanent location...done');
    return $flagstat;
}

sub _run_flagstat {
    my ($self, $bam_file, $flagstat_file) = @_;
    $self->status_message('Run and verify flagstat...');

    $flagstat_file ||= $bam_file.'.flagstat';
    $self->status_message("Flagstat file: $flagstat_file");
    my $cmd = "samtools flagstat $bam_file > $flagstat_file";
    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
    if ( not $rv or not -s $flagstat_file ) {
        $self->error_message($@) if $@;
        $self->error_message('Failed to run flagstat!');
        return;
    }
    my $flagstat = Genome::Model::Tools::Sam::Flagstat->parse_file_into_hashref($flagstat_file);
    $self->status_message('Flagstat output:');
    $self->status_message( join("\n", map { ' '.$_.': '.$flagstat->{$_} } sort keys %$flagstat) );
    if ( not $flagstat->{total_reads} > 0 ) {
        $self->error_message('Flagstat determined that there are no reads in bam! '.$bam_file);
        return;
    }
    $flagstat->{is_paired_end} = $flagstat->{reads_paired_in_sequencing} ? 1 : 0;
    if ( $flagstat->{is_paired_end} and $flagstat->{reads_marked_as_read1} != $flagstat->{reads_marked_as_read2} ) {
        $self->error_message('Flagstat determined that there are not equal pairs in bam! '.$bam_file);
        return;
    }

    $self->status_message('Run and verify flagstat...done');
    return $flagstat;
}
#</TransferBam>#

#<TransferFastq>#
sub _transfer_fastq_source_files {
    # TODO determine quality type
    my $self = shift;
    $self->status_message('Transfer source files...');

    # Derive dest file names and copy/gunzip to tmp dir in allocation
    my @source_files = $self->source_files;
    my $tmp_dir = $self->_tmp_dir;
    my (@destination_base_names, %read_counts);
    for ( my $i = 0; $i < @source_files; $i++ ) {
        my $source_file = $source_files[$i];
        $self->status_message("Source file: $source_file");
        my $lane = eval{ 
            my $attr = $self->instrument_data->attributes(attribute_label => 'lane');
            return $attr->attribute_value if $attr;
            return 1;
        };
        push @destination_base_names, sprintf(
            's_%s%s_sequence.txt',
            $lane, 
            ( @source_files == 1 ? '' : '_'.($i + 1) ),
        );
        my $destination_file = $tmp_dir.'/'.$destination_base_names[$i];
        $self->status_message("Destination file: $destination_file");
        my $cmd;
        if ( $source_file =~ /\.gz$/ ) { # zcat
            $cmd = "zcat $source_file | tee $destination_file";
        }
        else {
            $cmd = "tee $destination_file < $source_file";
        }
        my $line_count_file = $destination_file.'.count';
        $cmd .= " | wc -l > $line_count_file";
        my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
        if ( not $rv or not -s $destination_file ) {
            $self->error_message('Failed to transfer source file to tmp directory!');
            return;
        }
        my $read_count = $self->_get_read_count_from_line_count_file($line_count_file);
        return if not $read_count;
        $read_counts{$read_count} = 1;
        $self->status_message("Read count: $read_count");
    }

    # Read counts
    my @read_counts = keys %read_counts;
    if ( @read_counts > 1 ) {
        $self->error_message('Read counts are not the same for srouce files!');
        return;
    }
    $self->read_count( $read_counts[0] * @source_files );
    $self->is_paired_end( @source_files == 2 ? 1 : 0 );

    # Tar
    $self->status_message('Tar fastqs to tmp tar file...');
    my $tar_tmp_file = $tmp_dir.'/archive.tgz';
    $self->status_message("Tmp tar file: $tar_tmp_file");
    my $tar_ok = eval{ Genome::Sys->shellcmd(cmd => "tar cvzfh $tar_tmp_file -C $tmp_dir @destination_base_names"); };
    if ( not $tar_ok ) {
        $self->error_message('Failed to tar fastqs! From cmd: '.$@);
        return;
    }
    if ( not -s $tar_tmp_file ) {
        $self->error_message('Tar succeeded, but tar file does not exist!');
        return;
    }
    $self->status_message('Tar fastqs to tmp tar file...done');

    # Move tar file from tmp to main allocation
    $self->status_message('Move tmp tar file to permenant file...');
    my $tar_file = $self->instrument_data->allocation->absolute_path.'/archive.tgz';
    $self->status_message("Tar file: $tar_file");
    my $move_ok = File::Copy::move($tar_tmp_file, $tar_file);
    if ( not $move_ok ) {
        $self->error_message('Failed to move the tmp tar file!');
        return;
    }
    if ( not -s $tar_file ) {
        $self->error_message('Move of the tmp tar file succeeded, but tar file does not exist!');
        return;
    }
    $self->status_message('Move tmp tar file to permenant file...done');
    $self->final_data_file($tar_file);

    $self->status_message('Transfer source files...done');
    return 1;
}

sub _get_read_count_from_line_count_file {
    my ($self, $file) = @_;

    my $line_count = eval{ Genome::Sys->read_file($file); };
    if ( not defined $line_count ) {
        $self->error_message('Failed to open line count file! '.$@);
        return;
    }

    $line_count =~ s/\s+//g;
    if ( $line_count !~ /^\d+$/ ) {
        $self->error_message('Invalid line count! '.$line_count);
        return;
    }

    if ( $line_count == 0 ) {
        $self->error_message('Read count is 0!');
        return;
    }

    if ( $line_count % 4 != 0 ) {
        $self->error_message('Line count is not divisible by 4! '.$line_count);
        return;
    }

    return $line_count / 4;
}
#</TransferFastq>#

#<TransferSRA>#
sub _transfer_sra_source_file {
    my $self = shift;
    $self->status_message('Transfer SRA file...');

    #$self->status_message('');
    
    # copy sra to alloc
    # dump sam to sorted tmp bam
    # flagstat bam
    # move tmp bam to bam
    
    my ($source_file) = $self->source_files;
    my $bam_base_name = 'all_sequences.bam';
    my $tmp_bam_file_prefix = $self->_tmp_dir.'/all_sequences';
    my $tmp_bam_file = $tmp_bam_file_prefix.'.bam';
    $self->status_message("Source file: $source_file");
    $self->status_message("Temp bam file: $tmp_bam_file");
    my $cmd = "samtools sort -m 3000000000 -n $source_file $tmp_bam_file_prefix";
    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
    if ( not $rv or not -s $tmp_bam_file ) {
        $self->error_message($@) if $@;
        $self->error_message('Failed to run samtools sort and copy to to temp bam!');
        return;
    }


    $self->status_message('Transfer SRA file...done');
    return 1;
}
#</TransferSRA>#

#<Finish>#
sub _finish {
    my $self = shift;

    $self->status_message('Update properties on instrument data...');
    # File attribute
    my $instrument_data = $self->instrument_data;
    my $file_attribute_label = $self->file_attribute_label;#'bam_path'
    # TODO add original [start] format
    my $file_attribute_value = $self->final_data_file; # support more than one?
    $self->status_message(ucfirst(join(' ', split('_', $file_attribute_label))).': '.$file_attribute_value);
    $instrument_data->add_attribute(attribute_label => $file_attribute_label, attribute_value => $file_attribute_value);

    # Set attributes
    for my $attribute_label (qw/ read_count is_paired_end /) { # more?
        my $attribute_value = $self->$attribute_label;
        next if not defined $attribute_value; # error?
        $self->status_message(ucfirst(join(' ', split('_', $attribute_label))).': '.$attribute_value);
        $instrument_data->add_attribute(attribute_label => $attribute_label, attribute_value => $attribute_value);
    }
    $self->status_message('Update properties on instrument data...done');

    $self->status_message('Remove tmp dir...');
    File::Path::rmtree($self->_tmp_dir, 1);
    $self->status_message('Remove tmp dir...done');

    $self->status_message('Reallocate...');
    $self->instrument_data->allocations->reallocate;# with move??
    $self->status_message('Reallocate...done');

    return 1;
}
#<>#

sub _check_quality_scores {
    my ($self, $filename) = @_;

    my $lines_to_validate = 200;

    $self->status_message(sprintf(
            "Validating sample quality scores from first $lines_to_validate lines of $filename for import format %s.",
            $self->import_format));

    # grab some sample data from the file
    my $head = `head -$lines_to_validate $filename`;
    my @sample_lines = split("\n", $head);

    # We just want every 4th line
    my @quality_score_lines = @sample_lines[
    grep{0 == ($_ + 1) % 4} 0..$#sample_lines];

    for my $qs_line (@quality_score_lines) {
        unless ($self->_validate_quality_scores($qs_line)) {
            $self->error_message(sprintf(
                    "Couldn't validate quality scores for first $lines_to_validate lines of $filename as %s format.",
                    $self->import_format));
            die $self->error_message;
        }
    }
}

sub _validate_quality_scores {
    my ($self, $line) = @_;

    my %allowed_qs_chars = (
        'sanger fastq' => '[!-~]*',
        'solexa fastq' => '[;-~]*',
        'illumina fastq' => '[@-~]*',
    );

    my $filter_chars = $allowed_qs_chars{$self->import_format};
    $line =~ s/$filter_chars//g;
    chomp $line;

    # there should be nothing left after removing valid quality scores
    if (length($line)) {
        $line =~ s/(.)(?=.*?\1)//g; # find unique characters
        $self->error_message("Invalid characters in quality score: $line");
        return;
    }
    return 1;
}

1;

