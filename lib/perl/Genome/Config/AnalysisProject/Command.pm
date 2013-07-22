package Genome::Config::AnalysisProject::Command;

use strict;
use warnings;

use Genome::Command::Crud;
Genome::Command::Crud->init_sub_commands(
    target_class => 'Genome::Config::AnalysisProject',
    target_name => 'analysis_project',
    list => { show => 'id,name,created_by,_configuration_set_id,created_at,updated_at' },
    create => { do_not_init => 1 },
    update => { do_not_init => 1 },

);

class Genome::Config::AnalysisProject::Command {
    is => 'Command::Tree',
    doc => 'commands that deal with analysis projects',
};

1;
