package Genome::File::Fasta;

use strict;
use warnings;
use Genome;
use POSIX;

class Genome::File::Fasta {
    is => 'Genome::File::Base',
    has_optional => [
       _chromosome_info => {
           is => 'HashRef',
           doc => 'a hash ref containing chromosome name and lengths',
       },
       _chromosomes => {
           is => 'ArrayRef',
           doc => 'a hash ref containing chromosome name and lengths',
       },
       _genome_length => {
           is => 'Number',
           doc => 'the length of the fasta in bp',
       },
    ],

};

#here are some things one might want to do with a fasta file
# + get a list of chromosomes in the fasta
# + get a list of chromosome lengths in the fasta
# + get a sequence from the fasta
# + chunk up the genome into regions of size N
# + chunk up the genome into N regions
# + the above may all be available to it via the samtools faidx index

sub faidx_index {
    my $self = shift;
    my $expected_index_path =  $self->path . ".fai";
    if(-e $expected_index_path && -z $expected_index_path) {
        return $expected_index_path;
    }
    else {
        die "$expected_index_path either does not exist or has size 0\n";
    }
}

sub chromosome_name_list {
    my $self = shift;
    unless($self->_chromosomes) {
        $self->_cache_chromosome_info;
    }
    return @{$self->_chromosomes};
}

sub _cache_chromosome_info {
    my $self = shift;

    my $fh = Genome::Sys->open_file_for_reading($self->faidx_index);

    my @chrs;
    my %chr_info;
    my $total_genome_size = 0;
    
    while(my $line = $fh->getline) {
        chomp $line;
        my ($chr, $len) = split "\t", $line;
        push @chrs,$chr;
        $chr_info{$chr} = $len;
        $total_genome_size += $len;
    }

    $self->_chromosomes(\@chrs);
    $self->_chromosome_info(\%chr_info);
    $self->_genome_length($total_genome_size);
}

sub _regions_for_chunk {
    my ($self, $chunk_size, $n) = @_;

    my @chrs = map { [ $_, 1, $self->_chromosome_info->{$_} ] } $self->chromosome_name_list;
    my @regions;
    my $current_chr = shift @chrs;

    for(my $index = 0; $index < $n; $index++) {
        my $chunk_remaining = $chunk_size;
        @regions = ();
        while($chunk_remaining > 0 && $current_chr) {
            if((($current_chr->[2] - $current_chr->[1]) + 1) < $chunk_remaining) {
                push @regions, [$current_chr->[0],$current_chr->[1], $current_chr->[2]];
                $chunk_remaining -= ($current_chr->[2] - $current_chr->[1]) + 1;
                $current_chr = shift @chrs;
            }
            else {
                push @regions, [$current_chr->[0],$current_chr->[1], $current_chr->[1] + ($chunk_remaining - 1)];
                $current_chr->[1] += $chunk_remaining;
                $chunk_remaining = 0;
            }
        }
    }
    return @regions;
}

sub divide_into_chunks {
    my ($self, $total_chunks) = @_;

    my $chunk_size = ceil($self->total_genome_length / $total_chunks);
    
    my @chunks;
    for my $chunk_num (1..$total_chunks) {
        my @intervals = $self->_regions_for_chunk($chunk_size, $chunk_num);
        push @chunks, \@intervals;
    }
    return @chunks;
}

1;

