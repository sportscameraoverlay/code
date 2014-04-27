#This module stores all of the routines used by all modules
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 26/04/13 First version as perl module
# 1.01  PJ 05/05/13 Turned off progress display when debug is on
# 2.00  PJ 12/04/14 Added Environment checks subroutine
# 2.01  PJ 26/04/14 Fixed running script outside of sportscameraoverlay dir
#
###############################################################################

package SCPP::Common; 
use strict;
use warnings;
use SCPP::Config qw(:debug $ffmpeg_64bit_url $ffmpeg_32bit_url);
use File::Fetch;
use Archive::Extract;

BEGIN {
    require Exporter;
    our $VERSION = 2.01;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(progress check_env);
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

    #If debug is on turn off the progress as its messy in the logs
    if($debug){
        #We still want to know when things are done though
        print $process_name . "... Done\n" if( $percent_done == 100 );
        return 1;
    }

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
    return 1;
}
###############################################################################
#Check the envrionment to make sure all is well
#This subroutine will download the correct version of ffmpeg if it is not available
#More check should be done here, but lets start with getting the right FFMPEG! 
###############################################################################
sub check_env(){

    #Check if FFMPEG exists
    print "Checking for $program_dir/ffmpeg\n" if($debug);
    unless( -f "$program_dir/ffmpeg" and -x "$program_dir/ffmpeg" ){
        print "No FFMPEG binary found in sportscameraoverlay folder....\n";
        chomp (my $arch = `uname -m`);
        my $url = $ffmpeg_32bit_url;
        $url = $ffmpeg_64bit_url if( $arch =~ /64/ );
        
        print "Trying to download ffmpeg from $url\n";
        #Download ffmpeg
        my $ff = File::Fetch->new(uri => $url);
        my $ffmpeg_tar = $ff->fetch(to => \$program_dir) or die $ff->error; 
        #And extract it
        my $ae = Archive::Extract->new(archive => $ffmpeg_tar);
        $ae->extract or die $ae->error;
        #Then remove the archive file
        unlink $ffmpeg_tar or die $!;
    }
}
1;
