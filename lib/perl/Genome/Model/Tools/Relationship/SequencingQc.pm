package Genome::Model::Tools::Relationship::SequencingQc;

use strict;
use warnings;
use File::Basename;
use Genome;
use Genome::Info::IUB;
use Workflow;
use Workflow::Simple;

use List::MoreUtils qw/ uniq /;
class Genome::Model::Tools::Relationship::SequencingQc {
    is => 'Command',
    has => [
    output_dir => {
        is => 'Text',
        doc => 'the directory where you want results stored. If --save is enabled, this will be a symlink to the allocation.',
    },
    bams => {
        is => 'Text',
        is_many => 1,
        doc => 'Model(s) to add to group. Resolved from command line via text string.',
    },
    reference_fasta=> {
        is => 'Text',
        doc =>"reference the models were aligned to",
    },
    snp_files => {
        is =>'Text',
        is_many=>1,
    },
    use_sites_found_in_any_sample => {
        is=>"Boolean",
        default=>1,
        doc=>"This is the default method. Any sample will contribute variant sites, and that site will be polled across all included samples",
    },
    use_1000genomes_build37_sites => {
        is=>"Boolean",
        default=>0,
        doc=> "will override use sites found in any sample",
    },
    use_this_bed_file=> {
        is=>"Text",
        default=>0,
        doc=>"will override use sites found in any sample",
    },
    filename=> {
        is=>'Text',
        is_optional=>1,
        default=>"test",
    },
    min_coverage => {
        is => 'Number',
        is_optional=>1,
        default=>20,
        doc => 'the minimum coverage needed at a site to include it in the IBD analysis',
    },
    ped_file=> {
        is_optional=>1,
    },
    parent_relationship_cutoff => {
        default=>80,
        doc=>"In percent",
    },
    software_result => {
        is => 'Genome::SoftwareResult',
        doc => 'The output generated by running this command can be accessed via this property.',
        is_optional => 1,
    },
    result_users => {
        is => 'HASH',
        doc => 'The user information to use when getting or creating the software results',
    },
    ],
};

sub help_synopsis {
    return <<EOS
genome model-group relationship-qc --model-group=1745 --output-dir=/foo/bar/

EOS
}

sub execute {
    my $self = shift;

    my @bams = $self->bams;
    my @snp_files = $self->snp_files;

    my $output_dir = Genome::Sys->create_directory($self->output_dir);
    unless($output_dir) {
        $self->error_message("Unable to create output directory: " . $self->output_dir);
        return;
    }

    my $software_result = Genome::Model::Tools::Relationship::SequencingQcResult->get_or_create(
        output_dir => $output_dir,
        use_sites_found_in_any_sample => $self->use_sites_found_in_any_sample,
        use_1000genomes_build37_sites => $self->use_1000genomes_build37_sites,
        use_this_bed_file => $self->use_this_bed_file,
        bams => \@bams,
        snp_files => \@snp_files,
        reference_fasta => $self->reference_fasta,
        min_coverage => $self->min_coverage,
        ped_file => $self->ped_file,
        parent_relationship_cutoff => $self->parent_relationship_cutoff,
        test_name => $ENV{GENOME_SOFTWARE_RESULT_TEST_NAME} || undef,
        users => $self->result_users,
    );
    Genome::Sys->symlink_directory($software_result->output_dir, $output_dir);
    $self->software_result($software_result);

    if ($software_result->qc_status) {
        return $software_result->qc_status;
    }

    return 1;
}

sub _generate_data {
    my $self=shift;
    my $output_dir = $self->output_dir;

    my @sorted_bams = sort {$a cmp $b} $self->bams;
    unless(@sorted_bams >=2) {
        $self->error_message("You must supply at least 2 models to run this, check your command line, if that looks ok then check your head for nonsense.");
        return 0;
    }
    #TODO: verify all succeeded
    my $bed_file;
    if($self->use_this_bed_file) {
        $bed_file = $self->snv_bed;
        $self->debug_message("Using supplied bed file $bed_file");
    }
    elsif($self->use_1000genomes_build37_sites) {
        $self->debug_message("Using 1000 genomes build37 feature list for sites");
        my $feature_list = Genome::FeatureList->get("BFBC36724C5611E196CDFD9A7F526B77");
        my $temp_feature_file = $feature_list->generate_merged_bed_file();
        my $non_temp_bed_file = $self->output_dir . "/build37_variant_sites.bed";
        Genome::Sys->shellcmd(cmd=>"cp $temp_feature_file $non_temp_bed_file");
        $bed_file = $non_temp_bed_file;

    }
    elsif($self->use_sites_found_in_any_sample) {
        $self->debug_message("Using sites found in any 1 sample");
        $bed_file = $self->assemble_list_of_snvs($self->snp_files);
    }
    else {
        $self->error_message("All site selection methods appear to be null. Exiting.");
        return 0;
    }
    #    my ($self, $bams_ref, $bed_file, $reference_sequence_fasta, $n) = @_; <-- run_n_models_per_mpileup expectation

    my @pileup_files = $self->run_n_models_per_pileup(\@sorted_bams, $bed_file, $self->reference_fasta, 25); #25 seems a good number for speed/ cpu usage compromise
#    my $pileup_file = $self->run_mpileup(\@sorted_models, $bed_file);
#    unless($pileup_file) {
#        return;
#    }
#    my $beagle_input = $self->convert_mpileup_to_beagle($pileup_file, $self->min_coverage);
    my @bgl_inputs = map {$self->convert_mpileup_to_beagle($_, $self->min_coverage) } @pileup_files;

    my $beagle_input = $self->merge_bgl_outputs(@bgl_inputs);
    my $beagle_output = $self->run_beagle($beagle_input);
    my $relationship_matrix = $self->generate_relationship_table($beagle_output, $beagle_input);
    if($self->ped_file) {
        my $return_string = $self->return_pass_or_fail_based_on_ped($self->ped_file, $relationship_matrix);
        return $return_string;
    }
    #TODO: make auto-judging code to validate the family at this point
    return 1;

}

sub return_pass_or_fail_based_on_ped {
    my ($self, $ped_file, $relationship_matrix_file) = @_;
    my %ped_hash = $self->make_trios($ped_file, $relationship_matrix_file);
    my $matrix_fh = IO::File->new($relationship_matrix_file);
    $matrix_fh->getline; #throw away header
    while(my $line = $matrix_fh->getline) {
        chomp($line);
        my ($individual, @scores) = split"\t", $line;
        if(exists($ped_hash{$individual})) {
            my $dad_idx = $ped_hash{$individual}{'dad_index'};
            my $mom_idx = $ped_hash{$individual}{'mom_index'};
            my $dad_score = $scores[$dad_idx];
            my $mom_score = $scores[$mom_idx];
            if($dad_score < $self->parent_relationship_cutoff) {
                $self->error_message("Father of $individual seems unrelated, score $dad_score\n");
                return "Fail";
            }
            if($mom_score < $self->parent_relationship_cutoff) {
                $self->error_message("Mother of $individual seems unrelated, score $mom_score\n");
                return "Fail";
            }
        }
    }
    $self->debug_message(scalar(keys %ped_hash) . " children checked against their parents, all meet the cut off supplied to the filter of " . $self->parent_relationship_cutoff . "%");
    return "Pass";
}

sub make_trios {
    my ($self, $ped_file, $relationship_matrix_file) = @_;
    chomp(my $header_line = `head -n 1 $relationship_matrix_file`);
    my @fields = split "\t", $header_line;
    shift @fields; #throw away individual column
    my %person_to_index;
    my %ped_hash;
    for (my $i =0; $i < scalar(@fields); $i++) {
        $person_to_index{$fields[$i]}=$i;
    }
    my $fh = IO::File->new($ped_file);
    while(my $line = $fh->getline) {
        my ($family, $individual, $dad, $mom, $sex, $glf, $affected) = split "\t", $line;
        if($dad && $mom) {
            $ped_hash{$individual}{'dad_index'}=$person_to_index{$dad};
            $ped_hash{$individual}{'mom_index'}=$person_to_index{$mom};
        }
        elsif($dad || $mom) {
            $self->error_message("Previously we discarded incomplete peds upstream");
            $self->error_message("If this has changed, this tool needs to change.");
            die();
        }
    }
    return %ped_hash;
}




sub merge_bgl_outputs {
    my $self = shift;
    my @files = @_;
    my @fhs = map { IO::File->new($_) } @files;
    my $of_name = $self->output_dir . "/" . $self->filename . ".bgl.input";
    my $ofh = IO::File->new($of_name, ">");
    my @headers = map { $_->getline } @fhs;
    $ofh->print("I\tID");
    for my $line(@headers) {
        chomp($line);
        my @fields = split "\t", $line;
        shift @fields;
        shift @fields;
        $ofh->print("\t" . join("\t", @fields));
    }
    $ofh->print("\n");

    my @lines = map{$_->getline} @fhs;
    while(my $id = find_matching_line(\@fhs, \@lines)) {
        $ofh->print("M\t$id");
        for my $line(@lines) {
            chomp($line);
            my @fields = split "\t", $line;
            shift @fields;
            shift @fields;
            $ofh->print("\t" . join("\t", @fields));
        }
        $ofh->print("\n");

        @lines = map{$_->getline} @fhs;
    }
    $ofh->close;
    return $of_name;
}

sub all_files_open {
    my $fh = shift;
    for my $handle (@{$fh}) {
        if($handle->eof) {
            return 0;
        }
    }
    return 1;
}
sub find_matching_line {
    my $fh_ref = shift;
    my $line_ref = shift;
    my $not_synced = 1;
    while(all_files_open($fh_ref)) {
        my @chrs;
        my @positions;
        for my $line (@{$line_ref}) {
            my ($m, $id, undef)  = split "\t", $line;

            my ($chr, $pos) = split ":", $id;
            $DB::single=1 if $chr eq '2';
            push @chrs, $chr;
            push @positions, $pos;
        }

        my $i = find_lowest_pos(@chrs);
        my $j = find_lowest_pos(@positions);
        if($i != -1) {
            $line_ref->[$i]=$fh_ref->[$i]->getline;
            next;
        }
        if($j !=-1) {
            $line_ref->[$j]=$fh_ref->[$j]->getline;
            next;
        }
        if(($i==-1) && ($j==-1)) {
            return $chrs[0] . ":".  $positions[0];
        }
    }
    return 0;
}

sub find_lowest_pos {
    my @positions = @_;
    s/X/23/ for @positions;
    s/Y/24/ for @positions;
    my $least_position;
    my $least_idx;
    if(scalar(uniq @positions) ==1) {
        return -1;
    }
    for (my $i=0; $i < @positions; $i++) {
        if($positions[$i]=~m/[MGL]/) {
            return $i;
        }
        if (!$least_position || $least_position > $positions[$i]) {
            $least_position = $positions[$i];
            $least_idx = $i;
        }
    }
    return $least_idx;
}




sub assemble_list_of_snvs {
    my ($self, @snp_files) = @_;
    my %snvs;
    for my $snp_file (@snp_files) {
        my $snp_fh = Genome::Sys->open_file_for_reading($snp_file);
        while(my $line = $snp_fh->getline) {
            chomp($line);
            my ($chr, $start, $stop, $ref_var) = split "\t", $line;
            $snvs{$chr}{$stop}+=1;
        }
        $snp_fh->close;
    }
    #TODO: move output shit up into the class def
    my $name = $self->filename;
    $name =~ s/ /_/g;
    my $output_snvs = $self->output_dir . "/" . $name . ".union.bed";
    my $union_snv_fh = Genome::Sys->open_file_for_writing($output_snvs);
#    my $onepercent = scalar(@snp_files) / 100;  #we won't use this in the single family case
    for my $chr (sort keys %snvs) {
        for my $pos (sort keys %{$snvs{$chr}}) {

            my $start = $pos -1;
            my $stop = $pos;

            #     if($onepercent < $snvs{$chr}{$pos}) { ###only accept snps that appear in at least some of the samples
            $union_snv_fh->print("$chr\t$start\t$stop\n");
            #  }
        }
    }
    $union_snv_fh->close;
    return $output_snvs;
}


sub run_n_models_per_pileup {
    my ($self, $bams_ref, $bed_file, $reference_sequence_fasta, $n) = @_;
    my @fifty_model_array_refs;
    my %input_props;
    $input_props{bed_file}=$bed_file;
    $input_props{ref_fasta}=$reference_sequence_fasta;
    my @bams = @{$bams_ref};
    my @output_files;
    my $count=0;
    my @inputs;
    while(@bams) {
        my @temp_bams;
        while(scalar(@temp_bams) < $n && (scalar(@bams) >0)){
            push @temp_bams, shift @bams;
        }
        my @bam_group = @temp_bams;
        $input_props{"bams_$count"}=\@bam_group;
        my $output_file = $self->output_dir . "/group_$count/group_$count.vcf.gz";
        push @output_files, $output_file;
        $input_props{"output_$count"}=$output_file;
        push @inputs, "output_$count";
        push @inputs, "bams_$count";
        @temp_bams=();
        $count++;
    }
    my $workflow = Workflow::Model->create(
        name=> "$n sample parallel mpileup for qc",
        input_properties => [
        'bed_file',
        'ref_fasta',
        @inputs,
        ],
        output_properties => [
        'output',
        ],
    );
    $workflow->log_dir($self->output_dir);
    for(my $i=0; $i< $count; $i++) {
        my $mpileup_op = $workflow->add_operation(
            name=>"50 sample mpileup $i",
            operation_type=>Workflow::OperationType::Command->get("Genome::Model::Tools::Samtools::Mpileup"),
        );
        $workflow->add_link(
            left_operation=>$workflow->get_input_connector,
            left_property=>"bed_file",
            right_operation=>$mpileup_op,
            right_property=>"bed_file",
        );
        $workflow->add_link(
            left_operation=>$workflow->get_input_connector,
            left_property=>"ref_fasta",
            right_operation=>$mpileup_op,
            right_property=>"ref_fasta",
        );

        $workflow->add_link(
            left_operation=>$workflow->get_input_connector,
            left_property=>"bams_$i",
            right_operation=>$mpileup_op,
            right_property=>"bams",
        );
        $workflow->add_link(
            left_operation=>$workflow->get_input_connector,
            left_property=>"output_$i",
            right_operation=>$mpileup_op,
            right_property=>"output_vcf",
        );
        $workflow->add_link(
            left_operation=>$mpileup_op,
            left_property=>"output_vcf",
            right_operation=>$workflow->get_output_connector,
            right_property=>"output",
        );
    }
    my @errors = $workflow->validate;
    if (@errors) {
        $self->error_message(@errors);
        die "Errors validating workflow\n";
    }
    $self->debug_message("Now launching $count mpileup jobs");
    $DB::single=1;
    my $result = Workflow::Simple::run_workflow_lsf( $workflow, %input_props);
    unless($result) {
        $self->error_message( join("\n", map($_->name . ': ' . $_->error, @Workflow::Simple::ERROR)) );
        die $self->error_message("parallel mpileup workflow did not return correctly.");
    }
    return @output_files;
}










sub run_mpileup {
    my $self=shift;
    my $models_ref = shift;
    my $bed_file = shift;
    my @bams = map {$_->last_succeeded_build->whole_rmdup_bam_file} @{$models_ref};
    my $ref = $models_ref->[0]->reference_sequence_build->full_consensus_path("fa");
    #TODO: move output filenames into class def
    my $name = $self->filename;
    $name =~ s/ /_/g;
    my $output_vcf_gz = $self->output_dir . "/" . $name . ".vcf.gz";
    #samtools mpileup<BAMS>  -uf<REF>   -Dl<SITES.BED>  | bcftools view -g - | bgzip -c>  <YOUR GZIPPED VCF-LIKE OUTPUT>
    my $cmd = "samtools mpileup @bams -uf $ref -Dl $bed_file | bcftools view -g - | bgzip -c > $output_vcf_gz";
    my $rv = Genome::Sys->shellcmd( cmd => $cmd, input_files => [$bed_file, $ref, @bams]);
    if($rv != 1) {
        return;
    }
    return $output_vcf_gz;
}

sub convert_mpileup_to_beagle {
    my $self = shift;
    my $pileup_vcf_gz = shift;
    my $min_depth=shift;
    #TODO: move output files into class def
    my ($file, $path, $suffix) = fileparse($pileup_vcf_gz, ".vcf.gz");
    my $output_bgl_file = $path . "/" . $file . ".bgl.input";
    my $output_fh = Genome::Sys->open_file_for_writing($output_bgl_file);
    my $vcf_fh = IO::File->new("zcat $pileup_vcf_gz|");
    my @header;
    my $line;
    while($line = $vcf_fh->getline) {
        if($line =~m/^#/) {
            if($line =~m/^#CHROM/) {
                chomp($line);
                @header = split "\t", $line;
                last;
            }
        }
    }
##print header
    $output_fh->print("I\tID");
    splice(@header,0,9);
    for my $sample_name (@header) {
        $output_fh->print("\t$sample_name\t$sample_name");
    }
    $output_fh->print("\n");

    while($line= $vcf_fh->getline) {
        my $enough_depth=1;
        next if ($line =~m/INDEL/);

        chomp($line);
        my @fields = split "\t", $line;
        my $chr = $fields[0];
        my $pos = $fields[1];
        my $ref = $fields[3];
        my $alt = $fields[4];
        my $format = $fields[8];
        next if ($format !~ m/GT/);
        my @alts = split ",", $alt;
        unshift @alts, $ref;
        my @output_line =  ("M", "$chr:$pos");

        for (my $i =9; $i < scalar(@fields); $i++) {
            my $sample_field =  $fields[$i];
            my ($gt, $pl, $dp, $gq) = split ":", $sample_field;
            if($dp < $min_depth) {
                $enough_depth=0;
                last;
            }
            my ($all1, $all2)= split /[\/|]/, $gt;
            my $allele1 = $alts[$all1];
            my $allele2 = $alts[$all2];
            push @output_line, ($allele1, $allele2);
        }
        if($enough_depth) {
            $output_fh->print(join("\t", @output_line) . "\n");
        }
    }
    $output_fh->close();
    return $output_bgl_file;
}

sub run_beagle {
    my $self = shift;
    my $beagle_input = shift;
    my $output_dir = $self->output_dir;

    #./beagle.sh  fastibd=true unphased=cleft_lip/mpileup/bgl_from_vcf.test_input out=cleft_lip/mpileup/cleft_lip.out missing=?
    my $cmd = "java -Xmx14000m -jar $ENV{GENOME_SW}/beagle/installed/beagle.jar fastibd=true unphased=$beagle_input out=$output_dir/beagle missing=?";
    my $rv = Genome::Sys->shellcmd(cmd=>$cmd, input_files=>[$beagle_input]);
    if($rv != 1) {
        $self->error_message("Error running Beagle\n");
        return;
    }
    my ($file, $dir) = fileparse($beagle_input);
    return $dir . "beagle." . $file . ".fibd.gz";
}

sub generate_relationship_table {
    my $self = shift;
    my $beagle_output = shift;
    my $fibd_file = Genome::Sys->open_gzip_file_for_reading($beagle_output);
    my $markers_file = shift;
    #TODO: make output files all in class def
    my $output_file = $self->output_dir . "/relationship_matrix.tsv";
    my $output_fh = Genome::Sys->open_file_for_writing($output_file);
    my $high_relationship_file = $self->output_dir . "/strong_relationships.tsv";
    my $high_fh = Genome::Sys->open_file_for_writing($high_relationship_file);
    my $total_markers = `wc -l $markers_file`;
    $total_markers--; #account for header;
    my %relationships;
    while(my $line = $fibd_file->getline) {
        chomp($line);
        my ($first_guy, $second_guy, $start_marker, $stop_marker, $conf) = split "\t", $line;
        my $total_markers_covered;
        if(exists($relationships{$first_guy}{$second_guy})) {
            $total_markers_covered = $relationships{$first_guy}{$second_guy};
        }
        $total_markers_covered += ($stop_marker - $start_marker);
        $relationships{$first_guy}{$second_guy} = $total_markers_covered;
        $relationships{$second_guy}{$first_guy} = $total_markers_covered
    }
    my $i=0;
    my %table_hash;
    my @table;
    my @header_row;
    $output_fh->print("INDIVIDUAL");
    for my $first_guy (sort keys %relationships) {
        $table_hash{$first_guy}=$i;
        $i++;
        $output_fh->print("\t$first_guy");
        push @header_row, $first_guy;
    }
    for my $first_guy (sort keys %relationships) {
        for my $second_guy (sort keys %{$relationships{$first_guy}}) {
            unless(grep{/$second_guy/} @header_row) {
                $table_hash{$second_guy}=$i;
                $i++;
                $output_fh->print("\t$second_guy");
                push @header_row, $second_guy;
            }
        }
    }
    $output_fh->print("\n");



    for my $first_guy (sort keys %relationships) {
        my @high_relationship_line = ("$first_guy matches:");
        for my $second_guy (sort keys %{$relationships{$first_guy}}) {
            my $total_shared_markers = $relationships{$first_guy}{$second_guy};
            my $percent = sprintf("%0.2f", $total_shared_markers/$total_markers * 100);
            if($percent > 40) {
                push @high_relationship_line, "$second_guy:$percent";
            }
            my $j = $table_hash{$first_guy};
            my $k = $table_hash{$second_guy};
            $table[$j][$k]=$percent || 0;
        }
        $high_fh->print(join("\t", @high_relationship_line) . "\n");
    }
    $high_fh->close;
    for (my $j=0; $j < $i; $j++) {
        my $person_for_row = $header_row[$j];
        $output_fh->print("$person_for_row");
        for (my $k=0; $k < $i; $k++) {
            my $value = $table[$j][$k] || "N/A";
            $output_fh->print("\t$value");
        }
        $output_fh->print("\n");
    }
    $output_fh->close();
    return $output_file;
}

1;
