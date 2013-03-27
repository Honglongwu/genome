use strict;
use warnings;

use above "Genome";
use Fcntl ':mode';
use Genome::Utility::Test qw(abort run_ok);

use Test::More tests => 7;

eval {
    my $umask = umask;

    # setup
    my $td_path = File::Temp->newdir();
    ok(-d $td_path, 'made a temp directory to work in') or abort;
    run_ok(['chmod', 2775, $td_path], 'chmod that directory to have guid sticky') or abort;
    ok(umask 0077, 'set umask so that no group permissions are allowed') or abort;

    # make sure create_directory overrides umask
    my $cd_path = File::Spec->join($td_path, 'cd');
    Genome::Sys->create_directory($cd_path);
    ok(-d $cd_path, 'made a subdirectory');
    ok(group_write($cd_path), 'subdirectory made with Genome::Sys->create_directory has group write permissions');

    # verify mkdir, without overrides create_directory has, does not
    my $mkdir_path = File::Spec->join($td_path, 'mkdir');
    mkdir $mkdir_path;
    ok(-d $mkdir_path, 'made a subdirectory');
    ok(!group_write($mkdir_path), 'subdirectory made with mkdir does not have group write permissions');
};

sub group_write {
    my $path = shift;
    my $mode = (stat($path))[2];
    my $perms = S_IMODE($mode);
    my $group_write = ($perms & S_IWGRP) >> 3;
    return $group_write;
}
