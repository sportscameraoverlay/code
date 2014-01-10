#!/usr/bin/perl -w
#Script to run a system command and redirect all output to log file
#Requires the following
#1) debug level
#2) log file
#3) command (with arguments)
use strict;

my $debug = shift @ARGV;
my $out_file = shift @ARGV;
my @cmd = "@ARGV";

print "SYS_CMD: @cmd\n" if($debug > 1);
open STDOUT, ">>", $out_file or die "$!" if($debug <= 3);
open STDERR, ">>", $out_file or die "$!" if($debug <= 3);

`@cmd`;
exit $?;
