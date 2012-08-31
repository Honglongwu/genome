package Genome::Site::TGI::Synchronize::Classes::SetupProject; 

use strict;
use warnings;
use Genome;

class Genome::Site::TGI::Synchronize::Classes::SetupProject {
    table_name => <<SQL
    (
        --Setup Research Project
        select s.setup_id id, s.setup_name name 
        from setup_project\@oltp p
        join setup\@oltp s on s.setup_id = p.setup_project_id
        where p.project_type = 'setup project research'
        and p.setup_project_id > 2570000
        union all
        --Setup Work Order
        select wo.setup_wo_id id, s.setup_name name 
        from setup_work_order\@oltp wo
        join setup\@oltp s on s.setup_id = wo.setup_wo_id
        where wo.setup_wo_id > 2570000
    ) setup_project
SQL
    ,
    id_by => [
        id => { is => 'Text', },
    ],
    has => [
        name => { is => 'Text', },
    ],
    data_source => 'Genome::DataSource::GMSchema',
};

sub __display_name__ {
    return $_[0]->name.' ('.$_[0]->id.')';
}

1;

