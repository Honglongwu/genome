package Genome::Model::RnaSeq::Command::FpkmMatrix;

use strict;
use warnings;

use Genome;
use Statistics::Descriptive;

class Genome::Model::RnaSeq::Command::FpkmMatrix {
    is => 'Genome::Command::Base',
    has_input => [
        models => {
            is => 'Genome::Model::RnaSeq',
            is_many => 1,
            shell_args_position => 1,
            doc => 'RNAseq models to generate expression matrix.',
        },
        gene_fpkm_tsv_file => {
            doc => 'The output tsv file of gene-level FPKM values per model.',
        },
        isoform_fpkm_tsv_file => {
            doc => 'The output tsv file of isoform-level FPKM values per model.',
            is_optional => 1,
        },
        as_table => {
            doc => 'The output will be one line per single FPKM value.  This is useful for ggplot2.',
            default_value => 0,
        },
        model_identifier => {
            default_value => 'name',
            valid_values => ['name','subject_name'],
        },
    ],
};

sub help_synopsis {
    return <<"EOS"
    genome rna-seq fpkm-matrix --gene-fpkm-tsv-file=FILE1 --transcript-fpkm-tsv-file=FILE2
EOS
}

sub help_brief {
    return "Accumulate RNAseq FPKM values into a matrix.";
}

sub help_detail {
    return <<EOS
Accumulate FPKM values for genes and isoforms across a group of RNAseq models.
EOS
}


sub execute {
    my $self = shift;

    my @models = $self->models;
    # The values are attributes in the GTF file of known annotation
    my %feature_types = (
        gene => 'gene_id',
        isoform => 'transcript_id',
    );
    my @builds;
    my $annotation_build;
    my $reference_build;
    my %model_identifiers;
    my $method = $self->model_identifier;
    for my $model (@models) {
        my $identifier = $model->$method;
        if ( defined($model_identifiers{$identifier}) ) {
            die('Multiple models with '. $method .' : '. $identifier);
        } else {
            $model_identifiers{$identifier} = 1;
        }
        my $build = $model->last_succeeded_build;
        unless ($build) {
            $build = $model->latest_build;
            unless ($build) {
                die('Failed to find build for model: '. $model->id);
            }
        }
        push @builds, $build;
        my $model_reference_sequence_build = $model->reference_sequence_build;
        if ($reference_build) {
            unless ($reference_build->id eq $model_reference_sequence_build->id) {
                die('Mis-match reference sequence builds!');
            }
        } else {
            $reference_build = $model_reference_sequence_build;
        }
        my $model_annotation_build = $model->annotation_build;
        if ($annotation_build) {
            unless ($annotation_build->id eq $model_annotation_build->id) {
                die('Mis-match annotation builds!');
            }
        } else {
            $annotation_build = $model_annotation_build;
        }
    }
    my @model_identifiers = sort keys %model_identifiers;
    
    my $gtf_path = $annotation_build->annotation_file('gtf',$reference_build->id);
    $self->status_message('Loading known annotation file: '. $gtf_path);
    my $gff_reader = Genome::Utility::IO::GffReader->create(
        input => $gtf_path,
    );
    unless ($gff_reader) {
        die('Failed to read GTF file: '. $gtf_path);
    }
    my %gene_transcripts;
    while (my $data = $gff_reader->next_with_attributes_hash_ref) {
        my $attributes = delete($data->{attributes_hash_ref});
        $gene_transcripts{$attributes->{gene_id}}{gene_id}{$attributes->{gene_id}} = {};
        $gene_transcripts{$attributes->{gene_id}}{transcript_id}{$attributes->{transcript_id}} = {};
        $gene_transcripts{$attributes->{gene_id}}{gene_name} = $attributes->{gene_name};
    }
    $self->status_message('There are '. scalar(keys %gene_transcripts) .' genes in annotation file: '. $gtf_path);
    my @fpkm_tracking_headers;
    for my $build (@builds) {
        for my $feature_type (keys %feature_types) {
            my $fpkm_tracking = $build->data_directory .'/expression/'. $feature_type .'s.fpkm_tracking';
            unless (-e $fpkm_tracking) {
                die ('Failed to find '. $feature_type .' FPKM file: '. $fpkm_tracking);
            }
            my $fpkm_reader = Genome::Utility::IO::SeparatedValueReader->create(
                input => $fpkm_tracking,
                separator => "\t",
            );
            unless (@fpkm_tracking_headers) {
                @fpkm_tracking_headers = @{$fpkm_reader->headers};
            }
            my $match = 0;
            my $model_identifier = $build->model->$method;
            while (my $fpkm_data = $fpkm_reader->next) {
                my $gene_id = $fpkm_data->{gene_id};
                if ( defined($gene_transcripts{$gene_id}) ) {
                    my $type_id = $feature_types{$feature_type};
                    my $tracking_id = $fpkm_data->{tracking_id};
                    if ( defined($gene_transcripts{$gene_id}{$type_id}{$tracking_id}) ) {
                        if ( defined($gene_transcripts{$gene_id}{$type_id}{$tracking_id}{$model_identifier}) ) {
                            # If duplicate entries exist then keep the highest FPKM value
                            if ($gene_transcripts{$gene_id}{$type_id}{$tracking_id}{$model_identifier}->{FPKM} < $fpkm_data->{FPKM}) {
                                $gene_transcripts{$gene_id}{$type_id}{$tracking_id}{$model_identifier} = $fpkm_data;
                            }
                        } else {
                            $gene_transcripts{$gene_id}{$type_id}{$tracking_id}{$model_identifier} = $fpkm_data;
                            $match++;
                        }
                    }
                }
            }
            $self->status_message('There are '. $match .' matching '. $feature_type .'s in FPKM file: '. $fpkm_tracking);
        }
    }
    $self->status_message('Printing output FPKM tsv files...');
    my %tsv_writers;
    if ($self->as_table) {
        my $model_data_key = 'model_'. $self->model_identifier;
        my @output_headers = ($model_data_key,@fpkm_tracking_headers);
        for my $feature_type (keys %feature_types) {
            my $output_file_method = $feature_type .'_fpkm_tsv_file';
            my $output_file = $self->$output_file_method;
            my $tsv_writer = Genome::Utility::IO::SeparatedValueWriter->create(
                output => $output_file,
                separator => "\t",
                headers => \@output_headers,
            );
            unless ($tsv_writer) {
                die('Failed to open '. $feature_type .' FPKM output file: '. $output_file);
            }
            $tsv_writers{$feature_type} = $tsv_writer;
        }
        for my $gene_id (sort keys %gene_transcripts) {
            for my $feature_type (keys %feature_types) {
                my $tsv_writer = $tsv_writers{$feature_type};
                my $type_id = $feature_types{$feature_type};
                for my $tracking_id (sort keys %{$gene_transcripts{$gene_id}{$type_id}}) {
                    my %tracking_data = %{$gene_transcripts{$gene_id}{$type_id}{$tracking_id}};
                    if (scalar(keys %tracking_data) == (scalar(@model_identifiers))) {
                        for my $model_identifier (@model_identifiers) {
                            my %model_data = %{$tracking_data{$model_identifier}};
                            $model_data{$model_data_key} = $model_identifier;
                            $tsv_writer->write_one(\%model_data);
                        }
                    } else {
                        #is there a minimum number of samples(90%) that is required....
                    }
                }
            }
        }
    } else {
        my @output_headers = ('tracking_id','gene_id','gene_name',@model_identifiers);
        for my $feature_type (keys %feature_types) {
            my $output_file_method = $feature_type .'_fpkm_tsv_file';
            my $output_file = $self->$output_file_method;
            my $tsv_writer = Genome::Utility::IO::SeparatedValueWriter->create(
                output => $output_file,
                separator => "\t",
                headers => \@output_headers,
            );
            unless ($tsv_writer) {
                die('Failed to open '. $feature_type .' FPKM output file: '. $output_file);
            }
            $tsv_writers{$feature_type} = $tsv_writer;
        }
        for my $gene_id (sort keys %gene_transcripts) {
            for my $feature_type (keys %feature_types) {
                my $tsv_writer = $tsv_writers{$feature_type};
                my $type_id = $feature_types{$feature_type};
                for my $tracking_id (sort keys %{$gene_transcripts{$gene_id}{$type_id}}) {
                    my %tracking_data = %{$gene_transcripts{$gene_id}{$type_id}{$tracking_id}};
                    if (scalar(keys %tracking_data) == (scalar(@model_identifiers))) {
                        my %data = (
                            tracking_id => $tracking_id,
                            gene_id => $gene_id,
                            gene_name => $gene_transcripts{$gene_id}{gene_name},
                        );
                        for my $model_identifier (@model_identifiers) {
                            my %model_data = %{$tracking_data{$model_identifier}};
                            $data{$model_identifier} = $model_data{FPKM};
                        }
                        $tsv_writer->write_one(\%data);
                    } else {
                        #is there a minimum number of samples(90%) that is required....
                    }
                }
            }
        }
    }
    $self->status_message('Finished!');
    return 1;
}
