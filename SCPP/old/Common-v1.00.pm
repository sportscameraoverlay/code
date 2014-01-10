#This module stores all of the routines used by all modules
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 26/04/13 First version as perl module
#
###############################################################################

package SCPP::Common; 
use strict;
use warnings;

BEGIN {
    require Exporter;
    our $VERSION = 1.00;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(progress);
    our @EXPORT_OK = qw();
}

###############################################################################
#Display Progress
#Requires the folowing to be passed in:
# Process description
# Percent complete, 100 will print a new line and must be sent once done!
###############################################################################
sub progress($$){
	(my $process_name, my $percent_done) = @_;

	#Return cursor to the begining of the line
	print "\r"; 

	#Print the percent done
	printf '[%3.0f%%] ', $percent_done;

	#Print the process that is running
	if( $percent_done < 100 ) {
		print $process_name . "...";
	}else{
		#If 100% done end with a newline
		print $process_name . "... Done\n";
	}
}
1;
