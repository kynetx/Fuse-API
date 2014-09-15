#!/usr/bin/perl -w

use Getopt::Std;
use File::Copy;
use File::Path;
use File::Slurp;
use YAML::XS;
use DateTime;
use Net::Amazon::S3;
use Net::Amazon::S3::Client;
use Net::Amazon::S3::Client::Object;

use Data::Dumper;

use constant DEFAULT_CONFIG_FILE => './release.yml';
use constant DEFAULT_PROD_SERVER => "cs.kobj.net";
use constant DEFAULT_DEV_SERVER => "kibdev.kobj.net";
use constant DEFAULT_RULESET_DIR => "/rulesets";

# global options
use vars qw/ %clopt /;
my $opt_string = 'c:?hv:';
getopts( "$opt_string", \%clopt ) or usage();

usage() if $clopt{'h'} || $clopt{'?'};

my $timestamp = DateTime->now->set_time_zone('UTC');



die "Must specify version using -v switch" unless $clopt{"v"};
my $version = $clopt{"v"};
my $version_w_sep = $version . "_";

print "No registration file specified. Using " . DEFAULT_CONFIG_FILE . "\n" unless $clopt{'c'};
my $config = read_config($clopt{'c'});


my $prod_server =  $config->{'prod_rules_engine'} || DEFAULT_PROD_SERVER;
my $dev_server =  $config->{'dev_rules_engine'} || DEFAULT_DEV_SERVER;


my $aws_access_key_id     = $config->{"aws_key"};
my $aws_secret_access_key = $config->{"aws_secret"};

# If this doesn't work, 
my $s3 = Net::Amazon::S3->new(
      {   aws_access_key_id     => $aws_access_key_id,
          aws_secret_access_key => $aws_secret_access_key,
	  secure                => 1, # has to have Mozilla::CA installed to work
          retry                 => 1,
      }
  );

my $client = Net::Amazon::S3::Client->new( s3 => $s3 );

my $bucket = $client->bucket( name => $config->{"aws_bucketname"})  or die $s3->err . ": " . $s3->errstr;
my $ruleset_dir = $config->{"aws_ruleset_dir"} || DEFAULT_RULESET_DIR;

# warn "Amazon assets: ", Dumper $bucket->list_all;

die "No application map specified" unless defined $config->{"app_map"};

my $app_map = $config->{"app_map"};
my %new_name_map =  map { $_->{"dev"} => $_->{"prod"} }  values(%{ $app_map });
my $name_map = \%new_name_map;

# my $name_map = {
# 		"b16x9" => "fuse_vehicle",
# 		"b16x10" => "fuse_keys",
# 		"b16x11" => "fuse_carvoyant",
# 		"b16x12" => "b16x12",                 # carvoyant test
# 		"b16x13" => "fuse_error",
# 		"b16x16" => "fuse_owner",
# 		"b16x17" => "fuse_fleet",
# 		"b16x18" => "fuse_trips",
# 		"b16x19" => "fuse_common",
# 		"b16x20" => "fuse_fuel",
# 		"b16x21" => "fuse_maintenance",
# 		"b16x23" => "fuse_fleet_oauth"
# 	       };




my $target_dir = $version;

if (-e $target_dir) {
    my $new_dir = $target_dir.".".$timestamp;
    warn "Moving $target_dir to $new_dir";
    move($target_dir, $new_dir);
}

eval { mkpath($target_dir) };
if ($@) {
  print "Couldn't create directory $target_dir: $@";
}

my $flush_url = "http://$prod_server/ruleset/flush/";
my $flush_rids = [];

my $directory = '.';
opendir (DIR, $directory) or die $!;

while (my $file = readdir(DIR)) {

  # Use a regular expression to ignore files beginning with a period
  next if ($file =~ m/^\./);
  next if ($file !~ m/\.krl$/);
  print "$file\n";

  my $newfile = "$target_dir/$file";

  if (exists $app_map->{$file}) {
      push @{$flush_rids}, $version_w_sep. $app_map->{$file}->{"prod"} . ".prod";
  } else {
      warn "skipping $file in flush"
  }

  open(IN,  "< $file")                     or die "can't open $file: $!";
  open(OUT, "> $newfile")                  or die "can't open $newfile: $!";

  while (my $line = <IN>) {
      $line =~ s/(b16x\d+)/$version_w_sep$name_map->{$1}/g;

      print OUT $line

  }

}

closedir(DIR);

foreach my $rs ( keys %{$app_map}) {

   my $name = "rulesets/" . $version . "XYZ/" . $rs;
   print $name, "\n";

my $object = $bucket->object(
     key          => $name,
     acl_short    => 'public-read',
     content_type => 'text/plain',
   );
my $file_contant = read_file("$target_dir/$rs");
print $file_content, "\n\n";
#   $object->put('this is the public value');

}


print $flush_url . join(";", @{$flush_rids}), "\n";

1;

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

sub read_config {
    my ($filename) = @_;

    $filename ||= DEFAULT_CONFIG_FILE;

#    print "File ", $filename;
    my $config;
    if ( -e $filename ) {
      $config = YAML::XS::LoadFile($filename) ||
	warn "Can't open configuration file $filename: $!";
    }

    return $config;
}

