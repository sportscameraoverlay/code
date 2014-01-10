#This module is used to make any video transformations and create the final video
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 26/04/13 First version as perl module
#
###############################################################################

package SCPP::CreateVideo; 
use strict;
use warnings;
use Config;
$Config{useithreads} or die('Recompile Perl with threads to run this program.');
use threads;
use Time::HiRes qw(usleep);
use SCPP::Config qw(:debug :tmp :overlay :imgstab :video :vidoutset);
use SCPP::Common;

BEGIN {
    require Exporter;
    our $VERSION = 1.00;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(meltVideo convertFramerate stabilizeVideo);
    our @EXPORT_OK = qw();
}

#Video tmp files
my $melt_out_tmp = "$tmp_dir/melt_out_tmp$$.log";
my $img_stab_xmlfile = "$tmp_dir/contour_auth_vidstab$$.xml";


sub meltVideo($$$$);
sub convertFramerate($$);
sub stabilizeVideo($$);
sub runMelt($$);
##############################################################################
#Subroutine to blend videos with images with video using melt
#Requires:
#1)Input video filename
#2)Video framerate
#3)Length of video in sec
#4)Output video filename
#5)Path video filename
#
#Uses the globally defined output a/v parameters for output
#Also requires that all video framerates are the same
##############################################################################
sub meltVideo($$$$){

    (my $vid_in_file, my $length, my $vid_out_file, my $path_vid_file) = @_;
    my $num_frames = $length * $vid_out_framerate;
    my $frames_per_image = $vid_out_framerate / $images_per_sec;
    print "Framerate: $vid_out_framerate\n" if($debug);
    print "Number of frames: $num_frames\n" if($debug);

    my $command = "melt -track $vid_in_file in=0 out=$num_frames -track $tmp_dir/contour_img-%d.png ttl=$frames_per_image in=0 out=$num_frames -track $path_vid_file in=0 out=$num_frames -transition composite: a_track=0 b_track=1 geometry=0%,0%:100%x100%:$base_image_transparency -transition composite: a_track=0 b_track=2 geometry=75%,70%:30%,30%:100 -consumer avformat:$vid_out_file vcodec=$vid_out_codec vpre=$vid_out_quality r=$vid_out_framerate acodec=$audio_out_codec ab=$audio_out_bitrate";

    runMelt($command,"Generating Output Video");
}
##############################################################################
#Convert between framerates
#Requires:
#1)Input video filename
#2)Output video filename
#3)Output video framerate
##############################################################################
sub convertFramerate($$) {

    my ($in_filename, $out_filename) = @_;

    my $command = "melt $in_filename -consumer avformat:$out_filename vcodec=$vid_out_codec vpre=$vid_out_quality r=$vid_out_framerate";
    runMelt($command,"Changing Video Framerate");
}
##############################################################################
#Stabilize the video and convert between framerate
#Requires:
#1)Input video filename
#2)Output video filename
#3)Output video framerate
##############################################################################
sub stabilizeVideo($$){

    my ($in_filename, $out_filename) = @_;

    my $command = "melt $in_filename -filter videostab2 shakiness=$shakiness -consumer xml:$img_stab_xmlfile all=1 real_time=-2";
    runMelt($command,"Stabilizing Video. Pass 1/2");

    $command = "melt $img_stab_xmlfile -audio-track $in_filename -consumer avformat:$out_filename vcodec=$vid_out_codec vpre=$vid_out_quality";
    runMelt($command,"Stabilizing Video. Pass 2/2");

    #Remove the tmp xml file
    unlink $img_stab_xmlfile or die $!;
}
##############################################################################
#Run the melt command and grab the progress
#Requires the command that is to be run and the text to print out for progress
##############################################################################
sub runMelt($$){
    (my $command, my $process_name) = @_;

    print "Melt Command:\n$command\n" if($debug);
    progress($process_name, 0);

    #Create a thread to run melt
    my $thr1 = threads->create(sub {
            `$command -progress >$melt_out_tmp 2>&1`;
            my $exitstatus = $? >> 8;
            return ($exitstatus);
    });

    #While melt is running tail the log file and update the progress
    while($thr1->is_running) {
        usleep(1000*100); #Sleep for 100 milliseconds
        my $line = `tail -n 1 $melt_out_tmp`;
            if( $line =~ /Current Frame:\s+\d+, percentage:\s+(\d+)\r$/ ){
                progress($process_name, $1);
            }
    }

    #Both wait for the thread to finish running melt and die if it was unsuccessful
    die "Running Melt failed. Command run: $command\n" if($thr1->join() != 0);

    unlink($melt_out_tmp) or die "Failed to remove $melt_out_tmp: $!";
    progress($process_name, 100);
}

1;
