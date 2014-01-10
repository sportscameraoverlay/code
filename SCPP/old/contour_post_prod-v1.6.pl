#!/usr/bin/perl -w
#Script to help add GPS related info to videos taken with a contour GPS camera
#
#Requires the following packages if you are using ubuntu:
# melt
# ffmpeg
# libgd-gd2-perl
# libxml-libxml-perl
#The following packages are recommended
# libavformat-extra*
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
#
###############################################################################

use strict;
use Time::Local;
use Time::HiRes qw(usleep);
use File::Basename;
use Config;
$Config{useithreads} or die('Recompile Perl with threads to run this program.');
use threads;
use POSIX qw(strftime);
use GD;
$| = 1; #Disable buffering of stdout

#Video Output settings
my $vid_out_framerate = 30; 
my $vid_out_codec = 'libx264';
my $vid_out_quality = 'hq';
my $vid_out_bitrate = '5000k';
my $audio_out_codec = 'aac';
my $audio_out_bitrate = '160k';

#The Base overlay image
my $base_image_file = 'board-frosty.png';
#my $base_image_file = 'speedo.png';
my $base_image_transparency = 80;
my @overlay_pos = (0, 100); #X,Y percentage position
my $overlay_size = 60; #Percentage of original size

#Some colours (R,G,B)
my @green = (0,210,0);
my @black = (0,0,0);
my @red = (255,0,0);
my @blue = (0,0,255);
my @white = (255,255,255);
#Set the type of overlay
#my $overlay_type = 'speedo';
my $overlay_type = 'digital';
my $images_per_sec = 10; #This needs to be divisable wholey into the vid_out_framerate and GPS period!

#Image stabilization
my $stabilize_video = 1; #0 = no image stabilization, 1 = stabilize image
my $shakiness = 6; #How shakey the video is - Min=1, Max=10

#Options for debugging
my $save_subs = 1;
my $save_subs_GPGGA_file = "subs-GPGGA.txt";
my $save_subs_GPRMC_file = "subs-GPRMC.txt";
my $debug = 1;

#KML generation stuff
my $xml_format = 2; #Sets how the xml is printed...
my %kml_line_styles = (
	Track1 => {
		color => "ccff5555",
		width => "4",
		altitudeMode => "clampToGround",
	},
);
my $kml_track_style = '#Track1';
my $kml_flymode = "smooth";
my $kml_altitude = "0";
my $kml_tilt = "45";
my $kml_range = "300";
my $kml_altmode = "relativeToGround";
my $kml_position_marker = "/home/paul/contour_auth/target.png";
my $kml_pos_marker_scale = "1.2";

#Temp files/folders
my $tmpdir = "/tmp/contour_auth_$$/";
my $subs_file = "/tmp/contour_auth_subs$$.log";
my $melt_out_tmp = "/tmp/melt_out_tmp$$.log";
my $tmp_vid_file = "/tmp/tmpVid_$$.mp4";
my $tmp_vid_file2 = "/tmp/tmpVid2_$$.mp4";
my $img_stab_xmlfile = "/tmp/contour_auth_vidstab$$.xml";

#Some Fonts
my $ubuntufont='/usr/share/fonts/truetype/ubuntu-font-family/Ubuntu-B.ttf';
my $ubuntuCfont='/usr/share/fonts/truetype/ubuntu-font-family/Ubuntu-C.ttf';
my $sansfont='/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans-Bold.ttf';

#Text positioning and sizing
my $text_sizeL = 80;
my $text_sizeM = 40;
my $textHeight=160;
my $altTextboxLen = 245; #At 80pt one character is about 61pixels wide
my $altTextboxOff = 28;
my $mspeedTextboxLen = 184;
my $mspeedTextboxOff = 320;
my $mspeedFTextboxLen = 46; #At 40pt one char plus '.' is about 45pix wide
my $mspeedFTextboxOff = $mspeedTextboxLen + $mspeedTextboxOff;
my $speedTextboxLen = 184;
my $speedTextboxOff = 640;
my $speedFTextboxLen = 46;
my $speedFTextboxOff = $speedTextboxLen + $speedTextboxOff;

#Set the min/max angles in degrees and the needle length and centre for the speedo image
my $speedo_min_angle = 30;
my $speedo_max_angle = 330;
my $speedo_max_value = 100;
my $speedo_needle_length = 175;
my @speedo_centre = (200, 200);
my $speedo_centre_size = 15;
my $speedo_base_length = 20;
my $speedo_base_angle_offset = 10;
my $pi = 3.1415;
my $speedo_alt_text_size = 26;
my @speedo_altTextboxOff = (149, 176, 204, 232);
my $speedo_textHeight = 280;
my $speedo_altTextboxLen = 100;

#Other settings
my $knots2speed = 1.852; #Conversion from knots to km/h
my $vid_length_tol=2;

#Some Global vars that get set during running
my $video_length;
my @orig_vid_res;
my $orig_vid_bitrate;
my $orig_vid_framerate;
my $subtitle_length;
my $GPS_period;
my %GPS_data = (); #Hash of hashes to store GPS data
my %GPS_checksum_error = (); #Hash to store any GPS checksum errors 
my %string_length_errors = (); #Hash to store any string length errors
my @dup_time_errors; #Array to store and duplicate time entries as errors

#Subroutines
sub createSubs();
sub readSubs();
sub progress($$);
sub validateGpsChecksum($);
sub errorReport();
sub timeToEpoch($$);
sub checkGPSData();
sub generateOverlays();
sub positionImage($$$$$);
sub blendImages($);
sub meltVideo($$$$);
sub convertFramerate($$$);
sub stabilizeVideo($$$);
sub runMelt($$);
sub printString($$$$$$$$$$$);
sub overlay1($$$$$);
sub overlay2($$$$);
sub genKML();
sub latConv($);
sub longConv($);

###############################################################################
#Read in command line arguments
###############################################################################
die "You must specify an input video file\n" if($#ARGV != 0);
my $video_file = $ARGV[0];

#Create a name for this conversion (based on input filename) override in future?
my $file_name = $video_file;
$file_name =~ s/\.(\w\w\w\w?)$//;
my $project_name = fileparse($file_name);

#Set the video out file based on the input file
my $vid_out_file = $file_name . '-Overlay.mp4';

#Set the name of the kml file based on the input
my $kml_file = $file_name . '-Tour.kml';

###############################################################################
#Main Program
###############################################################################

createSubs();
readSubs();
#We can now remove the temp subs file if there are no errors
unlink($subs_file) or die $! if(!%GPS_checksum_error);
print "Video bitrate: $orig_vid_bitrate\n" if($debug);
print "Video Framerate: $orig_vid_framerate\n" if($debug);
print "GPS Period: $GPS_period\n" if($debug);

checkGPSData();
genKML();
exit 1;
mkdir $tmpdir;
generateOverlays();

if($stabilize_video){
    convertFramerate($video_file,$tmp_vid_file,$vid_out_framerate);
    stabilizeVideo($tmp_vid_file,$tmp_vid_file2,$vid_out_framerate);
    meltVideo($tmp_vid_file2,$vid_out_framerate,$subtitle_length,$vid_out_file);
    unlink($tmp_vid_file) or die $!;
    unlink($tmp_vid_file2) or die $!;
}elsif($orig_vid_framerate != $vid_out_framerate){
    convertFramerate($video_file,$tmp_vid_file,$vid_out_framerate);
    meltVideo($tmp_vid_file,$vid_out_framerate,$subtitle_length,$vid_out_file);
    unlink($tmp_vid_file) or die $!;
}else{
    meltVideo($video_file,$vid_out_framerate,$subtitle_length,$vid_out_file);
}

#Now clean up the tmp dir
unlink glob "$tmpdir/*.png";
rmdir $tmpdir;

errorReport();
exit 1;

##############################################################################
#Subroutine to blend videos with images with video using melt
#Requires:
#1)Input video filename
#2)Video framerate
#3)Length of video in sec
#4)Output video filename
#
#Uses the globally defined output a/v parameters for output
#Also requires that all video framerates are the same
##############################################################################
sub meltVideo($$$$){

    (my $vid_in_file, my $framerate, my $length, my $vid_out_file) = @_;
    my $num_frames = $length * $framerate;
    my $frames_per_image = $framerate / $images_per_sec;
    print "Framerate: $framerate\n" if($debug);
    print "GPS Period: $GPS_period\n" if($debug);
    print "Number of frames: $num_frames\n" if($debug);

    my $command = "melt -track $vid_in_file in=0 out=$num_frames -track $tmpdir/contour_img-%d.png ttl=$frames_per_image in=0 out=$num_frames -transition composite: a_track=0 b_track=1 geometry=0%,0%:100%x100%:$base_image_transparency -consumer avformat:$vid_out_file vcodec=$vid_out_codec vpre=$vid_out_quality r=$framerate acodec=$audio_out_codec ab=$audio_out_bitrate";

    runMelt($command,"Generating Output Video");
}
##############################################################################
#Convert between framerates
#Requires:
#1)Input video filename
#2)Output video filename
#3)Output video framerate
##############################################################################
sub convertFramerate($$$) {

    my ($in_filename, $out_filename, $out_framerate) = @_;

    my $command = "melt $in_filename -consumer avformat:$out_filename vcodec=$vid_out_codec vpre=$vid_out_quality r=$out_framerate";
    runMelt($command,"Changing Video Framerate");
}
##############################################################################
#Stabilize the video and convert between framerate
#Requires:
#1)Input video filename
#2)Output video filename
#3)Output video framerate
##############################################################################
sub stabilizeVideo($$$){

    my ($in_filename, $out_filename, $out_framerate) = @_;

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
##############################################################################
#Generate image overlays
##############################################################################
sub generateOverlays(){

    print "Images per sec: $images_per_sec\n" if($debug);
    print "GPS Period: $GPS_period\n" if($debug);

    my $process_name = "Creating overlay images";
    progress($process_name, 0);

    my $invalid_alt = "----";
    my $invalid_speed = "---";
    my $invalid_time = -1;
    
    #Calculate the number of images that need to be generated for each GPS reading (for interpolation of speed data)
    my $num_interpolated_pts = $images_per_sec * $GPS_period;
    my $num_of_images = $subtitle_length * $images_per_sec; #Number of images for progess display

    my $image_num = 0; #We have to use this as melt cant deal with any missing numbers in a sequence
    my $maxspeed = 0;
    foreach my $GPSline (sort {$a <=> $b} keys %GPS_data){
        #Set the altitude and speed to defaults
        my $altitude = $invalid_alt;
        my $speed = $invalid_speed;
        my $time = $invalid_time;

        $altitude = $GPS_data{$GPSline}{'altitude'} if(defined($GPS_data{$GPSline}{'altitude'}) and $GPS_data{$GPSline}{'altitude'} =~ /^\d+(\.\d+)?$/);
        $speed = $GPS_data{$GPSline}{'speed'} * $knots2speed if(defined($GPS_data{$GPSline}{'speed'}) and $GPS_data{$GPSline}{'speed'} =~ /^\d+(\.\d+)?$/);
        $time = $GPS_data{$GPSline}{'epoch'} if(defined($GPS_data{$GPSline}{'epoch'}));
        
        my $current_speed = $speed;
        my $next_speed;
        print "\nGPS Data line#: $GPSline\n" if($debug > 1);
        print "Epoch Time: $time\n" if($debug > 1);
        print "Current_speed: $current_speed\n" if($debug > 1);

        #Set the speed in the future to interpolate to
#        if(defined($GPS_data{ ($GPSline + 1) }{'fixStatus'}) and $GPS_data{ ($GPSline + 1) }{'fixStatus'} == 1){
        if(defined($GPS_data{($GPSline + 1)}{'speed'}) and $GPS_data{($GPSline + 1)}{'speed'} =~ /^\d+(\.\d+)?$/){
            $next_speed = $GPS_data{($GPSline + 1)}{'speed'} * $knots2speed;
        }else{
            $next_speed = $speed;
        }
        print "Next Speed: $next_speed\n" if($debug > 1);
        #Determine the amount to increase the speed by set to undef if not valid
        my $speed_inc;
        if(($current_speed ne $invalid_speed) and ($next_speed ne $invalid_speed)){
            $speed_inc = ($next_speed - $current_speed) / $num_interpolated_pts;
            print "Speed_inc: $speed_inc\n" if($debug > 1);
        }

        my $bim;
        #Create the overlay
        for( my $i = 0; $i < $num_interpolated_pts; $i++){
 
            #Calculate current_speed
            my $current_speed;
            if(defined($speed_inc)) {
                $current_speed = ($speed + ($i * $speed_inc)); 
            } else {
                $current_speed = $speed;
            }

            #Update maxpeed if the current speed is larger (and valid)
            if(($current_speed ne $invalid_speed) and ($maxspeed ne $invalid_speed) and ($current_speed > $maxspeed)){
                $maxspeed = $current_speed;
            }
        
            #Create the overlays for the digital type
            $bim = overlay1($altitude, $current_speed, $maxspeed, $time, 1) if($overlay_type eq 'digital');

            #Create the overlays for the speedo type
            $bim = overlay2($altitude, $current_speed, $maxspeed, $time) if($overlay_type eq 'speedo');
       
            #Place the overlay in the right position/size
            positionImage($bim, $overlay_pos[0], $overlay_pos[1], $overlay_size, $image_num);
            $image_num++;
            print "Image $image_num, Speed: $current_speed\n" if($debug > 1);
        }

        my $percent_done = (($image_num / $num_of_images) * 98);
        progress($process_name,$percent_done);
    }
    progress($process_name,100);
}

##############################################################################
#PositionImage - create an overlay image in the right res for the input video
#The following is passed in
#1)Reference to the overlay image
#2)x positioning of overlay image on final image in percent of max allowable
#3)y positioning of overlay image on final image in percent of max allowable
#4)Percentage to reduce/enlarge overlay image
#5)Image number
##############################################################################
sub positionImage($$$$$){

    (my $bim, my $x_pos, my $y_pos, my $size, my $num) = @_;

    #Convert % size to num
    $size = $size / 100;

    #Convert the image positioning in percent to pixels 
    $x_pos = ($orig_vid_res[0] - (${$bim}->width * $size)) * ($x_pos / 100);
    $y_pos = ($orig_vid_res[1] - (${$bim}->height * $size)) * ($y_pos / 100);

    #Create a new image in the correct res
    my $im = GD::Image->trueColor(1);
    $im = GD::Image->new($orig_vid_res[0],$orig_vid_res[1]);
    $im->alphaBlending(1);
    $im->saveAlpha(1);

    #Make the background transparent
    my $clear = $im->colorAllocateAlpha(255, 255, 255, 127);
    $im->fill(1,1,$clear);

    #Copy in the overlay image to the correct position
    $im->copyResampled(${$bim},$x_pos,$y_pos,0,0,${$bim}->width * $size,${$bim}->height * $size,${$bim}->width,${$bim}->height);

    #Print the created image out to the tmp dir
    my $full_image_name = $tmpdir . '/contour_img-' . $num . '.png';
    open IMAGE, ">", $full_image_name or die $!;
    binmode IMAGE;
    print IMAGE $im->png;
    close IMAGE or die $!;
}

##############################################################################
#Subroutine overlay1
#This subroutine is used to create an overlay image with digital data for 
#altitude, max speed and current speed
#The following is passed in
#1)Altitude
#2)Speed
#3)Max Speed
#4)epoch time - not currently used
#5)whether to print fractions of speed or not. 1 for yes, 0 for no.
#And this sub returns a reference to the image created
##############################################################################
sub overlay1($$$$$){
    
    (my $altitude, my $speed, my $maxspeed, my $epoch_time, my $frac) = @_;
    
    #Draw the overlay text over the base image
    my $bim = GD::Image->trueColor(1);
    $bim = newFromPng GD::Image($base_image_file);
    my $baseImageWidth = $bim->width;
    my $baseImageHeight = $bim->height;
    $bim->alphaBlending(1);
    $bim->saveAlpha(1);
 
    #Allocate some colours (R,G,B)
    my $text1 = $bim->colorAllocate(@red);

    my ($maxspeedInt, $maxspeedF, $speedInt, $speedF);
    #Check to make sure the input is numeric
    if($maxspeed =~ /^[\d\.]+$/){
        #Split the maxspeed vars into intergers and fractions
        $maxspeedInt = int($maxspeed);
        $maxspeedF = '.' . int(($maxspeed - $maxspeedInt) * 10);
    }else{
        $maxspeedInt = $maxspeed;
    }
    if($speed =~ /^[\d\.]+$/){
        #Split the speed vars into intergers and fractions
        $speedInt = int($speed);
        $speedF = '.' . int(($speed - $speedInt) * 10);
    }else{
        $speedInt = $speed;
    }

    #Convert the altitude to an interger
    $altitude = int($altitude) if($altitude =~ /^[\d\.]+$/);

    #Print the strings
    printString($text1,$ubuntufont,$text_sizeL,$altTextboxOff,$textHeight,$altitude,"Altitude",$altTextboxLen,$epoch_time,1,\$bim);
    printString($text1,$ubuntufont,$text_sizeL,$mspeedTextboxOff,$textHeight,$maxspeedInt,"Max_Speed",$mspeedTextboxLen,$epoch_time,1,\$bim);
    printString($text1,$ubuntufont,$text_sizeM,$mspeedFTextboxOff,$textHeight,$maxspeedF,"Max_Speed",$mspeedFTextboxLen,$epoch_time,0,\$bim) if(defined($maxspeedF));
    printString($text1,$ubuntufont,$text_sizeL,$speedTextboxOff,$textHeight,$speedInt,"Speed",$speedTextboxLen,$epoch_time,1,\$bim);
    printString($text1,$ubuntufont,$text_sizeM,$speedFTextboxOff,$textHeight,$speedF,"Speed_Fraction",$speedFTextboxLen,$epoch_time,0,\$bim) if(defined($speedF));

    #return a reference to the image created
    return \$bim;

}
##############################################################################
#Subroutine overlay2
#This subroutine is used to create an overlay image of an analog speedo
#The following is passed in
#1)Altitude
#2)Speed
#3)Max Speed
#4)epoch time - not currently used
#And this sub returns a reference to the image created
##############################################################################
sub overlay2($$$$){
    
    (my $altitude, my $speed, my $maxspeed, my $epoch_time) = @_;
    
    #Draw the overlay text over the base image
    my $bim = GD::Image->trueColor(1);
    $bim = newFromPng GD::Image($base_image_file);
    my $baseImageWidth = $bim->width;
    my $baseImageHeight = $bim->height;
    $bim->alphaBlending(1);
    $bim->saveAlpha(1);
 
    #Allocate some colours (R,G,B)
    my $needle1 = $bim->colorAllocate(@red);
    my $needle2 = $bim->colorAllocate(@green);
    my $black = $bim->colorAllocate(@black);
    my $text1 = $bim->colorAllocate(@white);

    my $deg_per_speed = ($speedo_max_angle - $speedo_min_angle) / $speedo_max_value;
    #Calculate the speed angles or set to min if data is invalid
    my ($speed_ang, $mspeed_ang);
    if($speed =~ /^[\d\.]+$/){
        $speed_ang = (($speed * $deg_per_speed) + $speedo_min_angle);
    }else{
        $speed_ang = $speedo_min_angle;
    }
    if($maxspeed =~ /^[\d\.]+$/){
        $mspeed_ang = (($maxspeed * $deg_per_speed) + $speedo_min_angle);
    }else{
        $mspeed_ang = $speedo_min_angle;
    }

    print "Angle: $speed_ang\n" if($debug > 2);

    #Internal subroutine to print needle position
    ########################################################
    sub print_needle($$$){
        #Requires an angle for the needle, a colour and the image reference

        my ($angle, $colour, $im_ref) = @_;
        my @tip_pos;
        $tip_pos[0] = $speedo_centre[0] - $speedo_needle_length*sin(($angle*$pi)/180);
        $tip_pos[1] = $speedo_centre[0] + $speedo_needle_length*cos(($angle*$pi)/180);
        my @base_pos1;
        $base_pos1[0] = $speedo_centre[0] + $speedo_base_length*sin((($angle + $speedo_base_angle_offset)*$pi)/180);
        $base_pos1[1] = $speedo_centre[0] - $speedo_base_length*cos((($angle + $speedo_base_angle_offset)*$pi)/180);
        my @base_pos2;
        $base_pos2[0] = $speedo_centre[0] + $speedo_base_length*sin((($angle - $speedo_base_angle_offset)*$pi)/180);
        $base_pos2[1] = $speedo_centre[0] - $speedo_base_length*cos((($angle - $speedo_base_angle_offset)*$pi)/180);
    
        #Set the line thickness to be slightly larger than normal
        ${$im_ref}->setThickness(2);
        my $poly = new GD::Polygon;
        $poly->addPt(@tip_pos); #tip
        $poly->addPt(@base_pos1); #base1
        $poly->addPt(@base_pos2); #base2

        # draw the polygon, filling it with a color
        ${$im_ref}->filledPolygon($poly,$colour);
    }
    ########################################################

    #Print the altitude in the centre
    $altitude = sprintf( '%04.0f', $altitude) if($altitude =~ /^[\d\.]+$/);
    my @altitude_chars = split(/ */, $altitude);
    for(my $i = 0; $i < 4; $i++){
        printString($text1,$ubuntufont,$speedo_alt_text_size,$speedo_altTextboxOff[$i],$speedo_textHeight,$altitude_chars[$i],"Altitude",$speedo_altTextboxLen,$epoch_time,0,\$bim);
    }

    #Print the current speed needle pos
    print_needle($speed_ang, $needle1, \$bim);

    #Print the max speed needle pos
    print_needle($mspeed_ang, $needle2, \$bim);
        
    #Lets also print some debug info if debug is set high enough
    if($debug and $debug > 3){ 
        printString($needle1,$ubuntufont,18,5,395,"Speed: $speed, Altitude: $altitude","Debug",395,$epoch_time,0,\$bim);
    }   

    #Fill in the centre of the speedo
    $bim->filledEllipse($speedo_centre[0],$speedo_centre[1],$speedo_centre_size,$speedo_centre_size,$black);

    return \$bim;
}
#############################################################################
#Print string onto image
#Requires:
#1) String colour
#2) String font
#3) String pt size
#4) String (box) position x
#5) String position y
#6) The actual string
#7) The string type (speed, altitude, max speed etc)
#8) The max string length in pixels
#9) Epoch of the image
#10) Left or right justify. 0 for left, 1 for right
#11) Reference to the image
##############################################################################
sub printString($$$$$$$$$$$){
    my ($colour, $font, $size, $x, $y, $string, $type, $max_len, $epoch, $justify, $im_ref) = @_;

    #Check string length and store warning if too long
    my @textLen = GD::Image->stringFT(0,$font,$size,0,0,0,$string);
    $string_length_errors{"$epoch.$type"} = "Epoch_ID: $epoch, $type string $string is too long! Actual: $textLen[2] pixels, Max: $max_len pixels." if($textLen[2] > $max_len);

    #Calculate the offset based on the string length (Right justifying the text)
    $x = ($max_len - $textLen[2] + $x) if($justify == 1);

    #Print the string
    ${$im_ref}->stringFT($colour, $font, $size, 0, $x, $y, $string);
}
##############################################################################
#Report on errors
##############################################################################
sub errorReport(){
    #Report on the checksum errors
    if(%GPS_checksum_error){
        print "\nThe following lines of the extracted subtitles contain NMEA GPS checksums that don\'t match reality:\n";
        foreach my $fail_line (sort {$a <=> $b} keys(%GPS_checksum_error)){
            print "line $fail_line, actual checksum $GPS_checksum_error{$fail_line}\n";
        }
        print "The extracted subtitles file($subs_file) has been retained\n";
    }
    #Report on strings that are too long
    if(%string_length_errors){
        print "\nThe following strings are to long:\n";
        foreach my $error (sort keys(%string_length_errors)){
            print "$string_length_errors{$error}\n";
        }
    }

    #Report on any duplicate times
    if(@dup_time_errors){
        print "\nThe following duplicate times were detected in the GPS data:\n";
        print @dup_time_errors;
        print "The later time(s) were deleted.\n";
    }
}
##############################################################################
#Check that the length of the video is the same as the length of the subtitles
##############################################################################
sub checkGPSData(){

    #First remove any duplicate times
    my %dup_times_check = ();
    foreach my $GPSline (sort keys %GPS_data){
        my $epoch_time = $GPS_data{ $GPSline }{ epoch };
        #We can only check for the dates that we have
        if(defined($epoch_time) and $epoch_time != -1){
            if(defined($dup_times_check{ $epoch_time })){
                push(@dup_time_errors, "Time: $epoch_time on Line $dup_times_check{$epoch_time} and line $GPS_data{$GPSline}{line_num}.\n");
                print "Duplicate time $epoch_time: Line $dup_times_check{$epoch_time} and line $GPS_data{$GPSline}{line_num}.\n" if($debug);
                delete $GPS_data{ $GPSline };
            }else{
                $dup_times_check{$epoch_time} = $GPS_data{$GPSline}{line_num};
            }
        }
    }

    #Calculate the length (time) of the subtitles
    my $GPS_data_lines = keys %GPS_data;
    $subtitle_length = $GPS_data_lines * $GPS_period;

    print "Video Length $video_length sec\n" if($debug);
    print "Subtitles Length $subtitle_length sec\n" if($debug);

    #Check if the length is within tolerance
    return 1 if($subtitle_length == $video_length);
    return 1 if(($subtitle_length > $video_length) and ($subtitle_length <= $video_length + $vid_length_tol));
    return 1 if(($subtitle_length < $video_length) and ($subtitle_length + $vid_length_tol >= $video_length));

    #Otherwise die
    die "Length of video differs from length of GPS data by " . ($video_length - $subtitle_length) . "sec. Not proceeding! (Change vid_length_tol if this is ok)!\n";
}

###############################################################################
#Subroutine that converts GPS date/time into epoch
#Time example: 171140.50 <- 5:11:40.5PM
#Date example: 220812 <- 22/08/2012
#Note input is in UTC time
###############################################################################
sub timeToEpoch($$){
    (my $time, my $date) = @_;

    #Check that the time and dates that are passed are valid 
    if (($time =~ /^(\d+(\.\d+)?)$/) and ($date =~ /^\d{6}$/)) {

        my $hour = substr($time,0,2);
        my $min = substr($time,2,2);
        my $sec = substr($time,4,2);
        my $part_sec = substr($time,6,2) if(length($time > 7));
        my $mday = substr($date,0,2);
        my $mon = (substr($date,2,2) - 1);
        my $year = substr($date,4,2);
        
        return timegm($sec,$min,$hour,$mday,$mon,$year) + $part_sec;
    }else {
        #Otherwise return -1 if date/time is invalid
        return -1;
    }
}

###############################################################################
#Subroutine to generate the subtitles file using ffmpeg
###############################################################################
sub createSubs(){

	my $process_name = "Extracting GPS data from video";
	progress($process_name, 0);
	#system("ffmpeg -i $video_file -an -vn -sbsf mov2textsub -scodec copy -f rawvideo $subs_file");
	my @output = `ffmpeg -loglevel info -i $video_file -vn -an -scodec copy -f rawvideo $subs_file 2>&1`;
	my $exitstatus = $? >> 8;
	die "\nFFMPEG failed with exitcode: $exitstatus\n\n@output\n" if( $exitstatus != 0 );

    #Grab info abotu the video
	progress($process_name, 90);
    foreach my $line (@output) {
        if( $line =~ /Duration: (\d\d):(\d\d):(\d\d(\.\d*)?), start: /){
            $video_length = $3 + ( ($2 + ( $1 * 60 )) * 60 );
        }
        #Stream #0:0(eng): Video: h264 (Main) (avc1 / 0x31637661), yuv420p, 1280x720 [SAR 1:1 DAR 16:9], 5231 kb/s, 25 fps, 25 tbr, 180k tbn, 50 tbc
        if( $line =~ /Stream #0.* Video: .+, .+, (\d+)x(\d+).*, (\d+(.\d+)?) kb\/s, (\d+(.\d+)?) fps,/){
            @orig_vid_res = ($1,$2);
            $orig_vid_bitrate = $3;
            $orig_vid_framerate = $5;
        }
    }
	progress($process_name, 100);
}

###############################################################################
#Subroutine to read the GPS data from the subtitles file generated with createSubs
################################################################################
#NMEA GPS info
###################################################
#Following data from http://aprs.gids.nl
#******************GPRMC Data********************** 
#$GPRMC,171135.00,A,3203.67014,S,11551.93499,E,2.573,247.07,220812,,,A*74 <-Contour example
#$GPRMC,220516.00,A,5133.32482,N,00042.23444,W,173.8,231.87,130694,004.2,W*70
#         1       2      3     4      5      6    7    8      9     10  11 12
#1   220516     Time Stamp  :$time
#2   A          validity - A-ok, V-invalid  :$validity
#3   5133.82    Latitude  :$lat
#4   N          North/South  :$latNS
#5   00042.24   Longitude  :$long
#6   W          East/West  :$longEW
#7   173.8      Speed in knots  :$speed
#8   231.8      True course (Track made good in degrees True)  :$trueCourse
#9   130694     Date Stamp  :$date
#10  004.2      Magnetic variation degrees (Easterly var. subtracts from true course) (Not used by contour camera)
#11  W          East/West (Not used by contour camera)
#12  *70        checksum
#
#******************GPGGA Data**********************
#$GPGGA,171013.00,3203.66845,S,11551.93951,E,1,10,0.79,19.0,M,-30.8,M,,*58 <-Contour example
#$GPGGA,hhmmss.ss,llll.lllll,a,yyyyy.yyyyy,a,x,xx,x.xx,xx.x,M,xxx.x,M,x.x,xxxx*hh
#           1         2      3      4      5 6  7  8    9  10   11 12 13  14  15
#1    = Time Stamp  :$time
#2    = Latitude  :$lat
#3    = North/South  :$latNS
#4    = Longitude  :$long
#5    = East/West  :$longEW
#6    = GPS quality indicator (0=invalid; 1=GPS fix; 2=Diff. GPS fix)  :$fixStatus
#7    = Number of satellites in use [not those in view]  :$numSat
#8    = Horizontal dilution of position (HDOP)  :$HDOP
#9    = Antenna altitude above/below mean sea level (geoid)  :$altitude
#10   = M
#11   = Geoidal separation (Diff. between WGS-84 earth ellipsoid and mean sea level. -=geoid is below WGS-84 ellipsoid)  :$geoidalSeparation
#12   = M
#13   = Age in seconds since last update from diff. reference station (Not used by contour camera)
#14   = Diff. reference station ID# (Not used by contour camera)
#15   = Checksum
################################################################################
sub readSubs(){

	my $process_name = "Reading GPS data";
	progress($process_name, 0);

    my ( @first_date , @second_date, @third_date );
    
	#These should be all the vars that the contour GPS outputs....
	my ( $time, $lat, $latNS, $long, $longEW, $fixStatus, $validity, $numSat, $HDOP, $altitude, $geoidalSeparation, $speed, $trueCourse, $date ); 

    my $line_num = 0; #line number in the subtitles file (used for debug if anything fails later)
    my $GPSline = 0; #Incremented for every occurance of GPRMC data found and used in the GPSdata hash as the key
    my $line;
    open SUBS_GPGGA, '>', $save_subs_GPGGA_file or die $! if($save_subs);
    open SUBS_GPRMC, '>', $save_subs_GPRMC_file or die $! if($save_subs);
    open FILE, $subs_file or die $!;
    while ($line = <FILE>) {

        #Keep track of the lines/data entries in the subs file (even if the data is not valid)
        $line_num++;
        $GPSline++ if($line =~ /\$GPRMC,/);
        
        #Remove non printable characters
        $line =~ s/[[:^print:]]+//g;

        #Check that the line is valid
        my $gps_checksum = validateGpsChecksum($line);
        if($gps_checksum eq -1) {
            ##Separate GPRMC and GPGGA data
			if ($line =~ /GPGGA,(.+)/) {
				#We only care about the info after the GPGGA
				$line=$1;
			    ($time, $lat, $latNS, $long, $longEW, $fixStatus, $numSat, $HDOP, $altitude, $geoidalSeparation) = split(/,/, $line);
			
                addGPSData($GPSline, 'time', $time);
                addGPSData($GPSline, 'lat', $lat);
                addGPSData($GPSline, 'latNS', $latNS);
                addGPSData($GPSline, 'long', $long);
                addGPSData($GPSline, 'longEW', $longEW);
                addGPSData($GPSline, 'fixStatus', $fixStatus);
                addGPSData($GPSline, 'numSat', $numSat);
                addGPSData($GPSline, 'HDOP', $HDOP);
                addGPSData($GPSline, 'altitude', $altitude);
                addGPSData($GPSline, 'geoidalSeparation', $geoidalSeparation);
                addGPSData($GPSline, 'lineNum', $line_num);
                
	    		#Also print these out to $savesubsfile if savesubs is set
	    		print SUBS_GPGGA "\$GPGGA,$line\n" if($save_subs);
		    }

    		if ($line =~ /GPRMC,(.+)/) {
    			#We only care about the info after the GPRMC
    			$line=$1;
    			($time, $validity, $lat, $latNS, $long, $longEW, $speed, $trueCourse, $date) = split(/,/, $line);

                addGPSData($GPSline, 'time', $time);
                addGPSData($GPSline, 'validity', $validity);
                addGPSData($GPSline, 'lat', $lat);
                addGPSData($GPSline, 'latNS', $latNS);
                addGPSData($GPSline, 'long', $long);
                addGPSData($GPSline, 'longEW', $longEW);
                addGPSData($GPSline, 'speed', $speed);
                addGPSData($GPSline, 'trueCourse', $trueCourse);
                addGPSData($GPSline, 'date', $date);
                addGPSData($GPSline, 'lineNum', $line_num);

                #Add the epoch time to the GPSdata hash (-1 if either time or date are invalid)
                my $epoch_time = timeToEpoch($time, $date);
                addGPSData($GPSline, 'epoch', $epoch_time);

                #We need to calculate the GPS period as this is quite important later on
                if($epoch_time != -1){
                    if(!@first_date) {
                        @first_date = ($GPSline,$epoch_time,$line_num);
                    }elsif(!@second_date) {
                        @second_date = ($GPSline,$epoch_time,$line_num);
                    }elsif(!@third_date) {
                        @third_date = ($GPSline,$epoch_time,$line_num);
                        
                        #Once we have three dates check that they are in order and the GPS period is consistant otherwise undef them and try again
                        $GPS_period = $second_date[1] - $first_date[1];
                        my $GPS_period_check = $third_date[1] - $second_date[1];
                        if(($second_date[0] - $first_date[0] != 1) or ($third_date[0] - $second_date[0] != 1) or ($GPS_period != $GPS_period_check)){
                            undef @first_date;
                            undef @second_date;
                            undef @third_date;
                            undef $GPS_period;
                            print "Dates not in order or GPS period not consistant! Trying again...\n" if($debug);
                        }
                    }
                }

    			#Also print these out to $savesubsfile if savesubs is set
    			print SUBS_GPRMC "\$GPRMC,$line\n" if($save_subs);
    		}
    	}elsif($gps_checksum ne -2){
            #Report on checksums that have failed (not lines that dont match the regex...)
            $GPS_checksum_error{ $line_num } = $gps_checksum;
        }
    }
	close FILE or die $!;
	close SUBS_GPGGA or die $! if($save_subs);
	close SUBS_GPRMC or die $! if($save_subs);

    #Check that we have successfully calculated the GPS_period otherwise there is no point continuing!
    die "\n\nNo valid dates found in GPS data, Cannot continue!\nThis is probably due to no GPS fix\n" if(!$GPS_period);
	
    progress($process_name, 100);
}

###############################################################################
#Validate GPS checksum
#Validates the gps string passed in against the checksum value on the end
###############################################################################
sub validateGpsChecksum($) {
	(my $gps_string) = @_;

    if($gps_string =~ /\$(GP.+)\*(..)/) {;
        my $gps_data = $1;
        my $checksum = lc($2);

        #Reverse the GPS data so we can read it from the start
        $gps_data = reverse($gps_data);
        #Process each character in the string
        my $build_checksum = chop($gps_data); 
        for(my $i = length($gps_data); $i >=1; $i--) {
            my $char = chop($gps_data);
            #XOR each character with the next (or last)
            $build_checksum = $build_checksum ^ $char;
        }
        #Convert the ascii string to Hex
        $build_checksum = unpack("H*", $build_checksum);

        #Return -1 if checksums match
        return -1 if($build_checksum eq $checksum);
    
        #Otherwise return the calculated checksum
        return $build_checksum;
    }else{
        #regex did not match, return -2
        return -2;
    }
}

###############################################################################
#Add data to GPS_data hash
#Must recieve 3 values
#1) GPS data line number
#2) var that is to be updated, eg: 'speed'
#3) value that should be stored
#Returns 1 on success, 2 if the value already exists
###############################################################################
sub addGPSData($$$) {
    (my $line, my $var, my $value) = @_;
    return 2 if(exists($GPS_data{ $line }{ $var }));
    $GPS_data{ $line }{ $var } = $value;
    return 1;
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

use XML::LibXML;
###############################################################################
#Subroutine to generate a KML tour based on the GPS points
###############################################################################
sub genKML(){

	#Print the static header info
	my $xml = XML::LibXML::Document->new('1.0', 'utf-8');
	my $kml = $xml->createElement("kml");
	$kml->setAttribute('xmlns'=> 'http://www.opengis.net/kml/2.2');
	$kml->setAttribute('xmlns:gx'=> 'http://www.google.com/kml/ext/2.2');

	#Print the static document header
	my $document = $xml->createElement("Document");
	$kml->appendChild($document);
	my $open_tag = $xml->createElement("open");
	$open_tag->appendTextNode(1);
	$document->appendChild($open_tag);

	#Now define the line style(s)
	foreach my $line_style (keys %kml_line_styles){
		my $style = $xml->createElement("Style");
		$style->setAttribute("id"=> "$line_style");
		$document->appendChild($style);
		my $linestyle_tag = $xml->createElement("LineStyle");
		$style->appendChild($linestyle_tag);
		#print colour
		my $color = $xml->createElement("color");
		$color->appendTextNode($kml_line_styles{$line_style}{'color'});
		$linestyle_tag->appendChild($color);
		#print width
		my $width = $xml->createElement("width");
                $width->appendTextNode($kml_line_styles{$line_style}{'width'});
                $linestyle_tag->appendChild($width);
		#print altitudeMode
                my $altitudeMode = $xml->createElement("altitudeMode");
                $altitudeMode->appendTextNode($kml_line_styles{$line_style}{'altitudeMode'});
                $linestyle_tag->appendChild($altitudeMode);
	}

    #Current position Icon
    my $style_pos = $xml->createElement("Style");
    $style_pos->setAttribute("id"=>"currentpos");
    $document->appendChild($style_pos);
    my $iconstyle = $xml->createElement("IconStyle");
    $style_pos->appendChild($iconstyle);
    my $icon = $xml->createElement("Icon");
    $iconstyle->appendChild($icon);
    my $href_icon = $xml->createElement("href");
    $href_icon->appendTextNode($kml_position_marker);
    $icon->appendChild($href_icon);
    my $scale_icon = $xml->createElement("scale");
    $scale_icon->appendTextNode($kml_pos_marker_scale);
    $iconstyle->appendChild($scale_icon);
    my $hotspot = $xml->createElement("hotSpot");
    $hotspot->setAttribute("x"=>"0.5");
    $hotspot->setAttribute("y"=>"0");
    $hotspot->setAttribute("xunits"=>"fraction");
    $hotspot->setAttribute("yunits"=>"fraction");
    $iconstyle->appendChild($hotspot);

    #Now plot the start position
    my $placemark_pos = $xml->createElement("Placemark");
    $document->appendChild($placemark_pos);
    my $styleurl_pos = $xml->createElement("styleUrl");
    $styleurl_pos->appendTextNode("#currentpos");
    $placemark_pos->appendChild($styleurl_pos);
    my $point_start = $xml->createElement("Point");
    $point_start->setAttribute("id"=>"currentpoint");
    $placemark_pos->appendChild($point_start);
    my $coordinates_start = $xml->createElement("coordinates");
    $point_start->appendChild($coordinates_start);

	#Now print the track (Placemark)
	my $placemark = $xml->createElement("Placemark");
	$document->appendChild($placemark);
	my $track_name = $xml->createElement("name");
	$track_name->appendTextNode($project_name . '-Track');
	$placemark->appendChild($track_name);
	my $styleurl = $xml->createElement("styleUrl");
	$styleurl->appendTextNode($kml_track_style);
	$placemark->appendChild($styleurl);
	my $linestring = $xml->createElement("LineString");
	$placemark->appendChild($linestring);
	
    #Now Print the Tour elements
	my $gx_tour = $xml->createElement("gx:Tour");
	$document->appendChild($gx_tour);
	my $name = $xml->createElement("name");
	$name->appendTextNode($project_name);
	$gx_tour->appendChild($name);
	my $gx_playlist = $xml->createElement("gx:Playlist");
	$gx_tour->appendChild($gx_playlist);

	#Fill in the coordinates for the track and the tour created above
	my $coordinates = $xml->createElement("coordinates");
	$linestring->appendChild($coordinates);
	foreach my $GPSline (sort {$a <=> $b} keys %GPS_data){
        #print out track
		my $lat = latConv($GPSline);
		my $long = longConv($GPSline);
		$coordinates->appendTextNode("$long,$lat,0\n");

        #Create flyto elements
        my $gx_flyto =  $xml->createElement("gx:FlyTo");
        $gx_playlist->appendChild($gx_flyto);
        #flyto - duration
        my $gx_duration = $xml->createElement("gx:duration");
        $gx_duration->appendTextNode($GPS_period);
        $gx_flyto->appendChild($gx_duration);
        #flyto - mode
        my $gx_flytomode = $xml->createElement("gx:flyToMode");
        $gx_flytomode->appendTextNode($kml_flymode);
        $gx_flyto->appendChild($gx_flytomode);
        #flyto - lookat
        my $lookat =  $xml->createElement("LookAt");
        $gx_flyto->appendChild($lookat);
        #flyto - lookat - longitude
        my $longitude = $xml->createElement("longitude");
        $longitude->appendTextNode($long);
        $lookat->appendChild($longitude);
        #flyto - lookat - latitude
        my $latitude = $xml->createElement("latitude");
        $latitude->appendTextNode($lat);
        $lookat->appendChild($latitude);
        #flyto - lookat - altitude
        my $altitude = $xml->createElement("altitude");
        $altitude->appendTextNode($kml_altitude);
        $lookat->appendChild($altitude);
        #flyto - lookat - heading
        my $heading = $xml->createElement("heading");
        $heading->appendTextNode($GPS_data{ $GPSline }{'trueCourse'});
        #$heading->appendTextNode("140");
        $lookat->appendChild($heading);
        #flyto - lookat - tilt
        my $tilt = $xml->createElement("tilt");
        $tilt->appendTextNode($kml_tilt);
        $lookat->appendChild($tilt);
        #flyto - lookat - range
        my $range = $xml->createElement("range");
        $range->appendTextNode($kml_range);
        $lookat->appendChild($range);
        #flyto - lookat - altitudemode
        my $altitudemode = $xml->createElement("altitudeMode");
        $altitudemode->appendTextNode($kml_altmode);
        $lookat->appendChild($altitudemode);

        #Now update the position marker
        if($GPSline == 1){
            #Set the start position (if its the start)
            $coordinates_start->appendTextNode("$long,$lat,0");
        }else{
            #Otherwise update the position
            my $gx_animatedupdate = $xml->createElement("gx:AnimatedUpdate");
            $gx_playlist->appendChild($gx_animatedupdate);
            my $gx_duration1 = $xml->createElement("gx:duration");
            $gx_duration1->appendTextNode($GPS_period);
            $gx_animatedupdate->appendChild($gx_duration1);
            my $update = $xml->createElement("Update");
            $gx_animatedupdate->appendChild($update);
            my $targethref = $xml->createElement("targetHref");
            $update->appendChild($targethref);
            my $change = $xml->createElement("Change");
            $update->appendChild($change);
            my $new_pos = $xml->createElement("Point");
            $new_pos->setAttribute("targetId"=> "currentpoint");
            $change->appendChild($new_pos);
            my $coordinates_new = $xml->createElement("coordinates");
            $coordinates_new->appendTextNode("$long,$lat,0");
            $new_pos->appendChild($coordinates_new);
       }
	}


	$xml->setDocumentElement($kml);
	print "$kml_file\n";
	open KML, '>', $kml_file or die $!;
	print KML $xml->toString($xml_format);
	close KML or die $!;
}


###############################################################################
#Convert Latitude from NMEA GPS format to Decimal format
#Requires the GPSdata line#
#Returns the lat decimal notation
###############################################################################
sub latConv($){
        (my $line) = @_;
        #NMEA format is DDMM.mmmm
	    my $NMEA_lat = $GPS_data{ $line }{'lat'};
        if($NMEA_lat =~ /(\d+)(\d\d\.\d+)/){
                my $decimal_lat = $1 + ($2 / 60);
                return 1001 if(!defined($GPS_data{ $line }{'latNS'}));
                $decimal_lat = $decimal_lat * -1 if($GPS_data{ $line }{'latNS'} =~ /s/i);
                return $decimal_lat;
        }else{
                return 1000;
        }
}
###############################################################################
#Convert Longitude from NMEA GPS format to Decimal format
#Requires the GPSdata line#
#Returns the long decimal notation
###############################################################################
sub longConv($){
        (my $line) = @_;
        #NMEA format is DDMM.mmmm       
	my $NMEA_long = $GPS_data{ $line }{'long'};
        if($NMEA_long =~ /(\d+)(\d\d\.\d+)/){
	        my $decimal_long = $1 + ($2 / 60);
		return 1001 if(!defined($GPS_data{ $line }{'longEW'}));
        	$decimal_long = $decimal_long * -1 if($GPS_data{ $line }{'longEW'} =~ /w/i);
        	return $decimal_long;
	}else{
		return 1000;
	}
}
