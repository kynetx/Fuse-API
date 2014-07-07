#!/usr/bin/perl -w

use Getopt::Std;
use File::Copy;
use File::Path;


# map for dev names to prod names

my $name_map = {
		"b16x9" => "fuse_vehicle",
		"b16x10" => "fuse_keys",
		"b16x11" => "fuse_carvoyant",
		"b16x12" => "b16x12",                 # carvoyant test
		"b16x13" => "fuse_error",
		"b16x16" => "fuse_owner",
		"b16x17" => "fuse_fleet",
		"b16x18" => "fuse_trips",
		"b16x19" => "fuse_common",
		"b16x20" => "fuse_fuel",
		"b16x21" => "fuse_maintenance",
		"b16x23" => "fuse_fleet_oauth"
	       };


 # don't need to map fuse_bootstrap_dev or fuse_bootstrap_prod since they're not supposed to be referenced anywhere

# global options
use vars qw/ %opt /;
my $opt_string = '?hv:';
getopts( "$opt_string", \%opt ) or usage();

usage() if $opt{'h'} || $opt{'?'};

die "Must specify version using -v switch" unless $opt{"v"};

my $version = $opt{"v"};
my $version_w_sep = $version . "_";

my $target_dir = $version;

if (-e $target_dir) {
    die "Directory $target_dir exists";
}

eval { mkpath($target_dir) };
if ($@) {
  print "Couldn't create directory $target_dir: $@";
}


my $directory = '.';
opendir (DIR, $directory) or die $!;

while (my $file = readdir(DIR)) {

  # Use a regular expression to ignore files beginning with a period
  next if ($file =~ m/^\./);
  next if ($file !~ m/\.krl$/);
  print "$file\n";

  my $newfile = "$target_dir/$file";

  open(IN,  "< $file")                     or die "can't open $file: $!";
  open(OUT, "> $newfile")                  or die "can't open $newfile: $!";

  while (my $line = <IN>) {
      $line =~ s/(b16x\d+)/$version_w_sep$name_map->{$1}/g;

      print OUT $line

  }

}

closedir(DIR);


#
# Message about this program and how to use it
#
sub usage {
    print STDERR << "EOF";

prepares a set of rulesets for deployment

usage: $0 [-h?] -v version

 -h|?       : this (help) message
 -v         : version

example: $0 -v v1

EOF
    exit;
}

