package Genome::Model::Tools::EpitopePrediction::ParseNetmhcMutant;

use strict;
use warnings;
use Data::Dumper;
use Genome;

class Genome::Model::Tools::EpitopePrediction::ParseNetmhcMutant {
    is => ['Genome::Model::Tools::EpitopePrediction::Base'],
    has_input => [
        netmhc_file => {
        	is => 'Text',
            doc => 'Raw output file from Netmhc',
        },
        parsed_file => {
        	is => 'Text',
            doc => 'File to write the parsed output',
        },
        output_type => {
            is => 'Text',
            doc => 'Type of epitopes to report in the final output - select \'top\' to report the top epitopes in terms of fold changes,  \'all\' to report all predictions ',
            valid_values => ['top','all'],
        },
        
    ],
};

sub help_brief {
    "FOR NETMHC : Parses output from NetMHC for MHC Class I epitope prediction; The parsed TSV file contains predictions for only those epitopes that contain the \"mutant\" SNV ",
}



sub execute {
    my $self = shift;
	my %netmhc_results;
	my %epitope_seq;
	my %position_score;
	
	my $type = $self->output_type;
	my $input_fh = Genome::Sys->open_file_for_reading($self->netmhc_file);
	my $output_fh = Genome::Sys->open_file_for_writing($self->parsed_file);
	
	while (my $line = $input_fh->getline) {
	chomp $line;
    if ( ($line =~ /^MT/) ||($line =~ /^WT/))  {

    	my @result_arr = split (/\t/,$line);
    	#print Dumper(@result_arr);
    	    	
    	my $position = $result_arr[1];
    	my $score = $result_arr[3];
    	my $epitope = $result_arr [ 2];
    	my $protein = $result_arr[0];
    	
    	my @protein_arr = split (/\./,$protein);
    	
    	#print Dumper(@protein_arr);
    	
    	my $protein_type = $protein_arr[0];
    	my $protein_name = $protein_arr[1];
    	my $variant_aa =  $protein_arr[3];
       
        $netmhc_results{$protein_type}{$protein_name}{$variant_aa}{$position} = $score;
        $epitope_seq{$protein_type}{$protein_name}{$variant_aa}{$position} = $epitope;
        
   	 }
	}

	print $output_fh join("\t","Gene Name","Point Mutation","Sub-peptide Position","MT score", "WT score","MT epitope seq","WT epitope seq","Fold change")."\n";
	my $rnetmhc_results = \%netmhc_results;
	my $epitope_seq = \%epitope_seq;
	my @score_arr;
	for my $k1 ( sort keys %$rnetmhc_results ) {
	 my @positions;
	   if ($k1 eq 'MT')
	   {
      #  print "$k1\t";

        for my $k2 ( sort keys %{$rnetmhc_results->{ $k1 }} ) {
            #print "$k2\t";
     
            for my $k3 ( sort keys %{$rnetmhc_results->{ $k1 }->{ $k2 }} ) {
                #print "\t$k3";
				%position_score = %{$netmhc_results{$k1}{$k2}{$k3}};
				@positions = sort {$position_score{$a} <=> $position_score{$b}} keys %position_score;
				my $total_positions = scalar @positions; 
				
				if ($type eq 'all')
				{
					
				
					for (my $i = 0; $i < $total_positions; $i++){
						
						
						if ($epitope_seq->{'MT'}->{$k2}->{$k3}->{$positions[$i]} ne $epitope_seq->{'WT'}->{$k2}->{$k3}->{$positions[$i]} )
						# Filtering if mutant amino acid present
						{
				
							print $output_fh join("\t",$k2,$k3,$positions[$i],$position_score{$positions[$i]})."\t";
							print $output_fh $rnetmhc_results->{ 'WT'}->{ $k2 }->{ $k3 }->{$positions[$i]}."\t";
							
							print $output_fh $epitope_seq->{'MT'}->{$k2}->{$k3}->{$positions[$i]}."\t";
							print $output_fh $epitope_seq->{'WT'}->{$k2}->{$k3}->{$positions[$i]}."\t";
						
							my $fold_change = $rnetmhc_results->{ 'WT'}->{ $k2 }->{ $k3 }->{$positions[$i]}/$position_score{$positions[$i]};
							my $rounded_FC = sprintf("%.3f", $fold_change);
							print $output_fh $rounded_FC."\n";	
						}
					}
				}
				if ($type eq 'top')
				{
					
					print $output_fh join("\t",$k2,$k3,$positions[0],$position_score{$positions[0]})."\t";
					print $output_fh $rnetmhc_results->{ 'WT'}->{ $k2 }->{ $k3 }->{$positions[0]}."\t";
				
					print $output_fh $epitope_seq->{'MT'}->{$k2}->{$k3}->{$positions[0]}."\t";
					print $output_fh $epitope_seq->{'WT'}->{$k2}->{$k3}->{$positions[0]}."\t";
					my $fold_change = $rnetmhc_results->{ 'WT'}->{ $k2 }->{ $k3 }->{$positions[0]}/$position_score{$positions[0]};
					my $rounded_FC = sprintf("%.3f", $fold_change);
					print $output_fh $rounded_FC."\n";	
				}
		
			}
				
           }
          }
        }

    
    
    return 1;
}



1;
