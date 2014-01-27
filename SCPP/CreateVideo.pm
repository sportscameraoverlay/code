#This module is used to make any video transformations and create the final video
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 26/04/13 First version as perl module
# 1.01  PJ 05/05/13 Updated debug output
# 1.02  PJ 20/06/13 Added config to change path positioning (or turn it off)
# 1.03  PJ 20/06/13 Fixed bugs with positioning of track
# 1.04  PJ 02/09/13 Added ability to rotate the input video
# 2.00  PJ 27/01/14 Using ffmpeg exclusively now (no more melt)
#
###############################################################################

package SCPP::CreateVideo; 
use strict;
use warnings;
use Config;
$Config{useithreads} or die('Recompile Perl with threads to run this program.');
use threads;
use Time::HiRes qw(usleep);
use SCPP::Config qw(:debug :tmp :video :vidoutset);
use SCPP::Common;

BEGIN {
    require Exporter;
    our $VERSION = 2.00;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(createVideo);
    our @EXPORT_OK = qw();
}

#Video tmp files
my $ffmpeg_out_tmp = "$tmp_dir/ffmpeg_out_tmp$$.log";

sub createVideo($$$$$$$$);
###############################################################################
#Subroutine to blend videos with images with video using FFMPEG
#Requires:
#1)Input video filename
#2)Whether to stop at after the shortest video/track/overlay has finished or not
#3)Output video filename
#4)Framerate of the overlay

#9)Whether to insert the track video or not
#10)Track video filename

#15)Amount of rotation to apply to the input video (in degrees)
#Approximate number of frames in output video (for progress display)
#
##############################################################################
sub createVideo($$$$$$$$){
    (my $vid_in_file, my $shortest, my $vid_out_file, my $overlay_fps, my $insert_track, my $track_vid_file, my $input_vid_rotation, my $approx_frames) = @_;

    my $process_name = "Creating output video";
    print "$process_name...\n" if($debug);
    progress($process_name, 0);
    
    #If there is a ffmpeg binary in the CWD then use that
    my $ffmpeg_cmd = "ffmpeg";
    $ffmpeg_cmd = "./ffmpeg" if(-f "./ffmpeg");
    
    #If we want to rotate the video do so:
    my $vid_in_rot_filter = '';
    $vid_in_rot_filter = " rotate=$input_vid_rotation*PI/180 [rot]; [rot]" if($input_vid_rotation);

    #If we are overlaying the track:
    my $track_overlay_filter = '';
    my $track_vid = '';
    $track_overlay_filter = "[ov1]; [ov1][2:v] overlay=0:0:shortest=$shortest" if($insert_track);
    $track_vid = "-i $track_vid_file" if($insert_track);

    #Preconstruct the filter_complex arguments:
    my $filters = "[0:v]" . $vid_in_rot_filter . "[1:v] overlay=0:0:shortest=$shortest" . $track_overlay_filter . " [out]";

    my $command = "$ffmpeg_cmd -progress $ffmpeg_out_tmp -loglevel fatal -hide_banner -y -i \'$vid_in_file\' -r $overlay_fps -i $tmp_dir/contour_img-%d.png $track_vid -filter_complex \'$filters\' -map \"[out]\" -vcodec $vid_out_codec -r $vid_out_framerate $vid_out_file";

    print "FFmpeg Command:\n$command\n" if($debug);

    #Create a thread to run ffmpeg
    my $thr1 = threads->create(sub {
        `$command 2>&1`;
        my $exitstatus = $? >> 8;
        return ($exitstatus);
    });

    #While ffmpeg is running tail the log file and update the progress
    while($thr1->is_running) {
        sleep(1);
        open FILE, $ffmpeg_out_tmp or die $!;
        my $line;
        while ($line = <FILE>) {
            if( $line =~ /frame=(\d+)$/ ){
#TODO could be more efficient!
                my $progress = ($1 / $approx_frames) * 100;
                progress($process_name, $progress);
            }
        }
        close FILE;
    }

    #Both wait for the thread to finish running ffmpeg and die if it was unsuccessful
    die "Running FFmpeg failed. Command run: $command\n" if($thr1->join() != 0);

    unlink($ffmpeg_out_tmp) or die "Failed to remove $ffmpeg_out_tmp: $!";
    progress($process_name, 100);

}
1;
