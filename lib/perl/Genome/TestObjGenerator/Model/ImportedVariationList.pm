package Genome::TestObjGenerator::Model::ImportedVariationList;
use Genome::TestObjGenerator::Model;
@ISA = (Genome::TestObjGenerator::Model);

use strict;
use warnings;
use Genome;

use Genome::TestObjGenerator::ProcessingProfile::ImportedVariationList;

my @required_params = ("subject_name");

sub generate_obj {
    my $self = shift;

    my $m = Genome::Model::ImportedVariationList->create(@_);
    return $m;
}

sub create_processing_profile_id {
    my $p = Genome::TestObjGenerator::ProcessingProfile::ImportedVariationList->setup_object();
    return $p->id;
}

sub create_subject_name {
#TODO need to fix subject name thing in these models
    return "human";
}

sub get_required_params {
    my $class = shift;
    my $super = $class->SUPER::get_required_params;
    my @all = (@$super, @required_params);
    return \@all;
}

1;

