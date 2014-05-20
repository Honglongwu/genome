package Genome::Config::AnalysisMenu::Command::Item::List;

use strict;
use warnings;
use Genome;

class Genome::Config::AnalysisMenu::Command::Item::List {
    is => 'Genome::Object::Command::List',
    has => [
        subject_class_name => {
            is_constant => 1,
            value => 'Genome::Config::AnalysisMenu::Item'
        },
        order_by => {default_value => 'name'},
        show => {default_value => 'id,name,created_by,created_at,updated_at,file_path'},
    ],
    doc => 'list Analysis Menu Items',
};

sub sub_command_sort_position { 1 }

1;
