#!/usr/bin/env perl
use strict;
use warnings;
use above "Genome";
use Test::More tests => 8; 

my $expected_out = $ENV{GENOME_TEST_INPUTS} . '/Genome-Model-ClinSeq-Command-GenerateClonalityPlots/2013-04-04/';

# "REBUILD" on the command-line when running the test sets the output to be the reference data set
# IMPORTANT: change the directory above to a new date when updating test data!
my $actual_out;
if (@ARGV and $ARGV[0] eq 'REBUILD') {
    warn "**** rebuilding expected output at $expected_out ****";
    mkdir $expected_out unless -d $expected_out;
    $actual_out = $expected_out;
}
else {
    $actual_out = Genome::Sys->create_temp_directory;
}

ok(-d $expected_out, "directory of expected output exists: $expected_out") or die;

#Get a somatic variation build
my $somvar_build_id = 135798051;
my $somvar_build = Genome::Model::Build->get($somvar_build_id);
ok($somvar_build, "Got somatic variation build from id: $somvar_build_id") or die;

my $cmd = Genome::Model::ClinSeq::Command::GenerateClonalityPlots->create(
    somatic_var_build => $somvar_build, 
    misc_annotation_db => Genome::Db->get("tgi/misc-annotation/human/build37-20130113.1"),
    chromosome => '22',
    verbose => 1, 
    output_dir => $actual_out, 
    common_name => 'HCC1395', 
);
$cmd->queue_status_messages(1);
my $r1 = $cmd->execute();
is($r1, 1, 'Testing for successful execution.  Expecting 1.  Got: '.$r1);

# The last column in the tsv file has output which varies randomly from run-to-run. :(
# We replace that value with ? before doing a diff so that we won't get spurious failures.
# In shell: cat AML54.clustered.data.tsv | perl -nae '$F[-1] = "?"; print join("\t",@F),"\n"' >| AML54.clustered.data.tsv.testmasked
#my $fhin = Genome::Sys->open_file_for_reading("$actual_out/AML54.clustered.data.tsv");
#my $fhout = Genome::Sys->open_file_for_writing("$actual_out/AML54.clustered.data.tsv.testmasked");
#while (my $row = <$fhin>) {
#    chomp $row;
#    my @fields = split("\t",$row);
#    $fields[-1] = "?";
#    $fhout->print(join("\t",@fields),"\n");
#}
#$fhout->close;

#Since we can not diff the pdf files, at least check for file creation...
my $pdf1 = $actual_out . "/HCC1395.clonality.pdf";
ok(-s $pdf1, "Found non-zero PDF file HCC1395.clonality.pdf");
my $pdf2 = $actual_out . "/HCC1395.clonality.cn2.pdf";
ok(-s $pdf2, "Found non-zero PDF file HCC1395.clonality.cn2.pdf");
my $pdf3 = $actual_out . "/HCC1395.clonality.filtered_snvs.pdf";
ok(-s $pdf3, "Found non-zero PDF file HCC1395.clonality.filtered_snvs.pdf");
my $pdf4 = $actual_out . "/HCC1395.clonality.filtered_snvs.cn2.pdf";
ok(-s $pdf4, "Found non-zero PDF file HCC1395.clonality.filtered_snvs.cn2.pdf");

# The differences test excludes files which always differ (embed dates, or are the subject of a masking as above).
my $temp_dir = "/tmp/last-generate-clonality-plots-result/";
my @diff = `diff -x '*.pdf' -x '*.R' -r $expected_out $actual_out`;
is(scalar(@diff), 0, "only expected differences") 
or do {
  for (@diff) { diag($_) }
  warn "*** if the above differences are not in error, rebuild the test data by running this test with REBUILD on the command-line ***";
  Genome::Sys->shellcmd(cmd => "rm -fr $temp_dir");
  Genome::Sys->shellcmd(cmd => "mv $actual_out $temp_dir");
};

#Genome::Sys->shellcmd(cmd => "rm -fr $temp_dir");
#Genome::Sys->shellcmd(cmd => "mv $actual_out $temp_dir");

