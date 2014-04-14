#!/usr/bin/perl -w
#Script to help add GPS related info to videos taken with a contour GPS camera
#
#Requires the following packages if you are using ubuntu:
# apt-get install perl libgd-gd2-perl libxml-libxml-perl
#Paul Johnston
###############################################################################
# History
###############################################################################
# 0.1  PJ 23/08/12 Original script
# 0.2  PJ 28/01/13 Added data validation
# 0.3  PJ 28/01/13 Fixed a few bugs removed old code
# 0.4  PJ 28/01/13 Fixed a few bugs added ability to fill in missing times
# 0.5  PJ 01/02/13 Added Overlay Image creation
# 0.6  PJ 03/02/13 Fixed bugs (regex) some code restructuring
# 0.7  PJ 04/02/13 Added progress to melt commands and some more restructuring
# 0.8  PJ 04/02/13 Cleaned up the image generation somewhat
# 0.9  PJ 04/02/13 Now generating the output video based on input video's name
# 0.10 PJ 09/02/13 Restructured to allow repositioning of overlays
# 0.11 PJ 09/02/13 Removed text label printing to screen now done in static image
# 0.12 PJ 12/02/13 Added "speedo" image overlay type
# 1.0  PJ 15/02/13 First Release that does pretty much what I want! (Bug fixes from v0.12)
# 1.1  PJ 15/02/13 More bug fixes (altitude now interger, few display issues, error reporting)
# 1.2  PJ 16/02/13 Added the option to perform image stabilization
# 1.3  PJ 16/02/13 Fixed bugs surrounding lack of GPS data
# 1.4  PJ 05/03/13 Now using the line number of the GPS data as the key for all GPS data (big change)
# 1.5  PJ 06/03/13 Fixed the video stabilization (now there are lots (4) of conversions for this)
# 1.6  PJ 19/03/13 Adding KML generation....
# 1.7  PJ 25/04/13 And then removed it into the kmlGen.pm module!
# 2.0  PJ 26/04/13 Modularised all code
# 2.1  PJ 16/06/13 Added option to only create KML file
# 2.2  PJ 20/06/13 Added more command line options. Prob should make these "longer" options
# 2.3  PJ 19/07/13 Added option to pass in a OSM map file
# 2.4  PJ 02/09/13 Added option to rotate input video file
# 2.5  PJ 02/09/13 Added option to batch process a directory full of files
# 2.6  PJ 27/01/14 Added option to use an external GPS file (-f option)
# 2.7  PJ 28/01/14 Removed the requirement for melt
# 2.8  PJ 15/04/14 Few small bugfixes, Also downloading ffmpeg if it doesn't exist
#
###############################################################################

use strict;
use warnings;
use File::Basename;
use Getopt::Long;
use File::Find;
use File::Spec;
use lib './SCPP';
use SCPP::KmlGen;
use SCPP::CreateVideo;
use SCPP::GoogleEarthRecord;
use SCPP::Common;
use SCPP::ReadGPSData;
use SCPP::Overlay;
use SCPP::Config qw(:debug :tmp :video :vidoutset :imgstab :overlay setOverlayValues $map_file);

$| = 1; #Disable buffering of stdout

sub run($);
###############################################################################
#Read in command line arguments
###############################################################################
check_env();

Getopt::Long::Configure ("bundling");

my $create_kml_only = 0;
my $insert_track = 0; #Disable until we get rid of GE
my $batch_mode = 0;
my $external_gps_file;

GetOptions ('v+' => \$debug, 'o=s' => \$overlay_type, 'k' => \$create_kml_only, 't' => \$insert_track, 's' => \$stabilize_video, 'm=s' => \$map_file, 'r=i' => \$input_vid_rotation, 'b=s' => \$batch_mode, 'f=s' => \$external_gps_file,);
die "You must specify an input video file or directory\n" if($#ARGV != 0);

#First set the CWD
$SCPP_dir = File::Spec->rel2abs(".") or die "Failed to convert CWD to a absolute path";
print "CWD: $SCPP_dir\n" if($debug > 1);

#Lets setup presets for the overlay type
setOverlayValues();

#Set the external GPS file to an absolute path
$external_gps_file = File::Spec->rel2abs($external_gps_file) or die "Failed to convert 
$external_gps_file to a absolute path" if($external_gps_file);

#Set the map file to an absolute path
$map_file = File::Spec->rel2abs($map_file) or die "Failed to convert 
$map_file to a absolute path" if($map_file);

###############################################################################
#Either process all files in the directory or just a single file.
#This code (if there are no errors) will call the run subroutine below
###############################################################################
#If we are processing a directory full of files find them all first
if($batch_mode){
    my $directory = $ARGV[0];
    print "Processing all files that end with $batch_mode from $directory\n";
    die "Batch mode specified but $directory doesn't exist or isn't a directory" if(! -d $directory);

    #Create the root temp dir
    my $tmp_dir_root = $tmp_dir;
    my $ge_path_vid_orig = $ge_path_vid;
    mkdir $tmp_dir_root or die "Failed to create dir $tmp_dir_root: $!";

    my @files;
    #For all files in the directory convert them
    find( \&wanted, $directory, no_chdir=>1);

    #Cleanup
    rmdir $tmp_dir_root or die "Failed to remove $tmp_dir_root: $!\n";
    exit 0;

    sub wanted{
        my $file = $_;
        my $absfile = File::Spec->rel2abs($file) or die "Failed to convert $file to a absolute path";
        if($absfile =~ /$batch_mode$/i){
            print "Processing: $absfile Started at: " . `date`;
            $tmp_dir = "$tmp_dir_root/$file/"; #Make a new tmp_dir for each new file
            $ge_path_vid = "$tmp_dir_root/$file/$ge_path_vid_orig";
            run($absfile);
    
            #Now clean up the tmp dir
            unlink glob "$tmp_dir/*.png" or warn "Failed to remove all image files $!" if(!$create_kml_only);
            rmdir $tmp_dir or die "Failed to remove $tmp_dir: $!";

            return 1;
        }else{
            print "Skipping $absfile as does not end in $batch_mode\n" if($debug);
        }
    }
}
#Otherwise just run on the single file
else{
    my $file = $ARGV[0];
    my $absfile = File::Spec->rel2abs($file) or die "Failed to convert $file to a absolute path";
    $ge_path_vid = "$tmp_dir/$ge_path_vid";
    run($absfile);
    
    #Now clean up the tmp dir
    unlink glob "$tmp_dir/*.png" or warn "Failed to remove all image files $!" if(!$create_kml_only);
    rmdir $tmp_dir or die "Failed to remove $tmp_dir: $!\n";

    exit 0;
}

###############################################################################
#Main Program (run subbroutine)
###############################################################################
sub run($){
    (my $video_file) = @_; 

    die "Video File $video_file does not exist\n" if(! -f $video_file);
    die "Video File $video_file is not readable\n" if(! -r $video_file);

    #Some Global vars that get set during running
    my $video_length;
    my @orig_vid_res;
    my $GPS_in_video;
    my $orig_vid_bitrate;
    my $orig_vid_framerate;
    my $subtitle_length;
    my $GPS_period;
    my %GPS_data; #Hash of hashes to store GPS data

    #Create a name for this conversion (based on input filename) override in future?
    my $file_name = $video_file;
    $file_name =~ s/\.(\w\w\w\w?)$//;
    $file_name =~ tr/\$#@~!&*()[];:?^ `\\//d; #Tidy up the file name
    my $project_name = fileparse($file_name);

    #Set the video out file based on the input file
    my $vid_out_file = $file_name . '-Overlay.mp4';

    #Set the name of the kml file based on the input
    my $kml_file = $file_name . '-Tour.kml';


    #Create a tmp working dir
    mkdir $tmp_dir or die "Failed to create dir $tmp_dir: $!";

    #Grab the subtiles from the video file and store video info
    my $subs_file = $tmp_dir . $subs_file_name;
    ($video_length, $orig_vid_res[0], $orig_vid_res[1], $GPS_in_video, $orig_vid_bitrate, $orig_vid_framerate) = createSubs($video_file, $subs_file);
    #If we don't want to change the framerate:
    $vid_out_framerate = $orig_vid_framerate if(!$vid_out_framerate);

    #Set the GPS data to an external source if we have requested this
    if($external_gps_file){
        print "Using external GPS file $external_gps_file\n" if($debug);
        $subs_file = $external_gps_file;
    }else{
        #Otherwise check that there is GPS data in the video file!
        die "No GPS data in video file and external GPS file not specified with -f option. Cannot continue!\n" unless($GPS_in_video);
    }

    #Read the GPS info from the subtitles file 
    ($GPS_period, my $subs_file_err) = readGPSfile(\%GPS_data, $subs_file);

    #Print some debug
    print "Video bitrate: $orig_vid_bitrate\n" if($debug);
    print "Video Framerate: $orig_vid_framerate\n" if($debug);
    print "GPS Period: $GPS_period\n" if($debug);

    #Turn off the track if requested
    undef @track_pos unless($insert_track or $create_kml_only);

    #And check the GPS data
    $subtitle_length = checkGPSData(\%GPS_data, $video_length, $GPS_period);
    #Check if the length is within tolerance
    if($subtitle_length > $video_length + $vid_length_tol_minus){
        die "GPS data is " . ($subtitle_length - $video_length) ."sec longer than the video. Not proceeding!\nChange vid_length_tol_minus (currently set to $vid_length_tol_minus sec) if this is ok!\n";
    }
    if($video_length > $subtitle_length + $vid_length_tol_plus){
        die "Video length is " . ($video_length - $subtitle_length) ."sec longer than the GPS data. Not proceeding!\nChange vid_length_tol_plus (currently set to $vid_length_tol_plus sec) if this is ok!\n";  
    }
    GPSPointsCalc(\%GPS_data);

    #Generate the KML file for GE
    genKML(\%GPS_data, $kml_file, $project_name, $GPS_period) if(@track_pos);

    #If there are no errors in the subtitles remove the tmp file
    unlink($subs_file) or die $! if(!$subs_file_err);

    #Exit now if we only want the KML file
    if($create_kml_only){
        return 1;
    }

    #Record the KML tour in GE
    recordTourGE($kml_file, $ge_path_vid, $subtitle_length, $vid_out_framerate) if(@track_pos);

    #Generate the overlays
    generateOverlays(\%GPS_data, $GPS_period, $orig_vid_res[0], $orig_vid_res[1], $subtitle_length, $images_per_sec, $overlay_type);

    #Construct the final video
    my $length;
    $length = $video_length if($video_length <= $subtitle_length);
    $length = $subtitle_length if($video_length > $subtitle_length);
    my $approx_frames = $length * $vid_out_framerate;
    createVideo($video_file,$stop_at_shortest,$vid_out_file,$images_per_sec,$insert_track,$ge_path_vid,$input_vid_rotation, $approx_frames);

    return 1;
}
