package Genome::TestObjGenerator::Model::ReferenceSequence;
use Genome::TestObjGenerator::Model;
@ISA = (Genome::TestObjGenerator::Model);

use strict;
use warnings;
use Genome;
use Genome::TestObjGenerator::ProcessingProfile::ReferenceSequence;

my @required_params = ("subject");

sub generate_obj {
    my $self = shift;

    my $m = Genome::Model::ReferenceSequence->create(@_);
    return $m;
}

sub create_processing_profile_id {
    my $p = Genome::TestObjGenerator::ProcessingProfile::ReferenceSequence->setup_object();
    return $p->id;
}

sub get_required_params {
    my $class = shift;
    my $super = $class->SUPER::get_required_params;
    my @all = (@$super, @required_params);
    return \@all;
}

sub create_subject {
    return Genome::Sample->create(name => Genome::TestObjGenerator::Util::generate_name("test_subject"));
}

1;

