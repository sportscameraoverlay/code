#!/usr/bin/perl -w
#Script to help add GPS related info to videos taken with a contour GPS camera
#
#Requires the following packages if you are using ubuntu:
# melt
# ffmpeg
# libgd-gd2-perl
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
#
###############################################################################

use strict;
use Time::Local;
use Time::HiRes qw(usleep);
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
my $base_image_file = 'contour_auth-baseimage.png';

#Options for debugging
my $save_subs = 1;
my $save_subs_GPGGA_file = "subs-GPGGA.txt";
my $save_subs_GPRMC_file = "subs-GPRMC.txt";
my $debug = 0;

#Temp files/folders
my $tmpdir = "/tmp/contour_auth_$$/";
my $subs_file = "/tmp/contour_auth_subs$$.log";
my $melt_out_tmp = "/tmp/melt_out_tmp$$.log";
my $tmp_vid_file = "/tmp/tmpVid$$.mp4";

#Some Fonts
my $ubuntufont='/usr/share/fonts/truetype/ubuntu-font-family/Ubuntu-B.ttf';
my $ubuntuCfont='/usr/share/fonts/truetype/ubuntu-font-family/Ubuntu-C.ttf';
my $sansfont='/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans-Bold.ttf';

#Text positioning
#All dimensions are based off 720p res
my $textHeight=696;
my $altTextboxLen = 184; #At 60pt one character is about 46pixels wide
my $altTextboxOff = 32;
my $mspeedTextboxLen = 138;
my $mspeedTextboxOff = 240;
my $speedTextboxLen = 138;
my $speedTextboxOff = 440;

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

#Subroutines
sub createSubs();
sub readSubs();
sub progress($$);
sub validateGpsChecksum($);
sub errorReport();
sub timeToEpoch($$);
sub checkLength();
sub generateOverlays();
sub createImage($$$$$);
sub blendImages($);
sub meltVideo($$$$);
sub convertFramerate($$$);
sub runMelt($$);
sub printString($$$$$$$$$$);
sub test();

###############################################################################
#Read in command line arguments
###############################################################################
die "You must specify an input video file\n" if($#ARGV != 0);
my $video_file = $ARGV[0];

#Set the video out file based on the input file
my $vid_out_file = $video_file;
$vid_out_file =~ s/\.(\w\w\w\w?)$/-Overlay.mp4/;

###############################################################################
#Main Program
###############################################################################

createSubs();
readSubs();
#We can now remove the temp subs file if there are no errors
unlink($subs_file) or die $! if(!%GPS_checksum_error);
print "Video bitrate: $orig_vid_bitrate\n" if($debug);
print "Video Framerate: $orig_vid_framerate\n" if($debug);

checkLength();

mkdir $tmpdir;
generateOverlays();

if($orig_vid_framerate != $vid_out_framerate){
    convertFramerate($video_file,$tmp_vid_file,$vid_out_framerate);
    meltVideo($tmp_vid_file,$vid_out_framerate,$subtitle_length,$vid_out_file);
    unlink($tmp_vid_file) or die $!;
}else{
    meltVideo($video_file,$vid_out_framerate,$subtitle_length,$vid_out_file);
}

#Now clean up the tmp dir
unlink glob "$tmpdir/*.png";
rmdir $tmpdir;

#test();
errorReport();

##############################################################################
#Test output
##############################################################################
sub test(){
    foreach my $time (sort keys %GPS_data){
        my $time_string = strftime "%a %b %e %H:%M:%S %Y", localtime($time);
        if (defined($GPS_data{ $time }{'fixStatus'}) and $GPS_data{ $time }{'fixStatus'} == 1){
            my $speed = $knots2speed * $GPS_data{ $time }{'speed'};
            print "$time_string, $speed km/h, Date: $GPS_data{ $time }{'date'}\n";
    	}elsif(defined($GPS_data{ $time }{'date'}) and length($GPS_data{ $time }{'date'}) > 1) {
            print "$time_string, Date: $GPS_data{ $time }{'date'}\n";
        }else{
            print "$time_string\n";
        }
    }
}
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
    my $frames_per_image = $framerate / $GPS_period;
    print "Framerate: $framerate\n" if($debug);
    print "GPS Period: $GPS_period\n" if($debug);
    print "Number of frames: $num_frames\n" if($debug);
    print "Frames per image: $frames_per_image\n" if($debug);

    my $command = "melt -track $vid_in_file in=0 out=$num_frames -track $base_image_file in=0 out=$num_frames -track $tmpdir/contour_img-%d.png ttl=$frames_per_image in=0 out=$num_frames -transition composite: a_track=0 b_track=1 geometry=0%,0%:100%x100%:100 -transition composite: a_track=0 b_track=2 geometry=0%,0%:100%x100%:100 -consumer avformat:$vid_out_file vcodec=$vid_out_codec vpre=$vid_out_quality r=$framerate acodec=$audio_out_codec ab=$audio_out_bitrate";

    print "Melt Command:\n$command\n" if($debug);
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
#Run the melt command and grab the progress
#Requires the command that is to be run and the text to print out for progress
##############################################################################
sub runMelt($$){
    (my $command, my $process_name) = @_;

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

    my $process_name = "Creating overlay images";
    progress($process_name, 0);
    my $num_of_images = $subtitle_length / $GPS_period;

    my $image_num = 0; #We hve to use this as melt cant read epoch numbers in a sequence
    my $maxspeed = 0;
    foreach my $time (sort keys %GPS_data){
        #Set the altitude and speed to defaults
        my $altitude = "---";
        my $speed = "--";

        if(defined($GPS_data{ $time }{'fixStatus'}) and $GPS_data{ $time }{'fixStatus'} == 1){

            $altitude = sprintf("%.0f", $GPS_data{ $time }{'altitude'});
            $speed = sprintf("%.0f", $GPS_data{ $time }{'speed'} * $knots2speed);
        
            #Update maxpeed if speed is larger
            $maxspeed = $speed if( $speed > $maxspeed );
        }

        #Now create the image with the data
        createImage($altitude, $speed, $maxspeed, $time, $image_num);
        $image_num++;
        
        my $percent_done = (($image_num / $num_of_images) * 98);
        progress($process_name,$percent_done);
    }
    
    progress($process_name,100);
}

##############################################################################
#CreateImage
#The following is passed in
#1)Altitude
#2)Speed
#3)Max Speed
#4)epoch time - not currently used
#5)Image number
##############################################################################
sub createImage($$$$$){

    (my $altitude, my $speed, my $maxspeed, my $epoch_time, my $num) = @_;

    my $res=$orig_vid_res[1] / 720; #All dimensions are based off 720p res

    #Create base image in the correct res
    my $im = GD::Image->trueColor(1);
    $im = GD::Image->new(1280*$res,720*$res);
    $im->alphaBlending(0);
    $im->saveAlpha(1);

    #Allocate some colours
    my $black = $im->colorAllocate(0,0,0);
    my $text1 = $im->colorAllocate(255,0,0);
    my $text2 = $im->colorAllocate(0,0,255);
    my $clear = $im->colorAllocateAlpha(255, 255, 255, 127);

    #Make the background transparent
    $im->fill(1,1,$clear);

    #TODO This should be done in the base image (static)
    #Print headings 
    #$image->stringFT($fgcolor,$fontname,$ptsize,$angle,$x,$y,$string)
    $im->stringFT($text2,$ubuntufont,22*$res,0,50*$res,626*$res,"Altitude");
    $im->stringFT($text2,$ubuntufont,22*$res,0,260*$res,626*$res,"Max Speed");
    $im->stringFT($text2,$ubuntufont,22*$res,0,450*$res,626*$res,"Current Speed");
    #Print Units
    $im->stringFT($text2,$ubuntuCfont,30*$res,0,214*$res,696*$res,"m");
    $im->stringFT($text2,$ubuntuCfont,28*$res,0,380*$res,696*$res,"km/h");
    $im->stringFT($text2,$ubuntuCfont,28*$res,0,580*$res,696*$res,"km/h");

    #Print the strings
    printString($text1,$ubuntufont,60*$res,$altTextboxOff*$res,$textHeight*$res,$altitude,"Altitude",$altTextboxLen,$epoch_time,\$im);
    printString($text1,$ubuntufont,60*$res,$mspeedTextboxOff*$res,$textHeight*$res,$maxspeed,"Max_Speed",$mspeedTextboxLen,$epoch_time,\$im);
    printString($text1,$ubuntufont,60*$res,$speedTextboxOff*$res,$textHeight*$res,$speed,"Speed",$speedTextboxLen,$epoch_time,\$im);

    #Print the created image out to the tmp dir
    my $full_image_name = $tmpdir . '/contour_img-' . $num . '.png';
    open IMAGE, ">", $full_image_name or die $!;
    binmode IMAGE;
    print IMAGE $im->png;
    close IMAGE or die $!;
}

##############################################################################
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
#10) Reference to the image
##############################################################################
sub printString($$$$$$$$$$){
    my ($colour, $font, $size, $x, $y, $string, $type, $max_len, $epoch, $im_ref) = @_;

    #Check string length and store warning if too long
    my @textLen = GD::Image->stringFT(0,$font,$size,0,0,0,$string);
    $string_length_errors{$epoch}{$type} = "$type string $string is too long! Actual: $textLen[2] pixels, Max: $max_len pixels." if($textLen[2] > $max_len);

    #Calculate the offset based on the string length (Right justifying the text)
    $x = ($max_len - $textLen[2] + $x);

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
    #TODO Fix this!
    #Report on strings that are too long
#    if(%GPS_checksum_error){
    #       print "\nThe following strings are to long:\n";
    #   foreach my $fail_line (sort keys(%string_length_errors)){
    #       foreach my $type (keys(%string_length_errors{$fail_line}){
    #           print "Epoch_ID: $fail_line,$string_length_errors{$type}\n";
    #       }
    #   }
    #}
}
##############################################################################
#Check that the length of the video is the same as the length of the subtitles
##############################################################################
sub checkLength(){
    my $subtile_min_time = 9999999999;
    my $subtile_max_time = -1;
    foreach my $epoch_time (keys %GPS_data){
        $subtile_min_time = $epoch_time if($epoch_time < $subtile_min_time);
        $subtile_max_time = $epoch_time if($epoch_time > $subtile_max_time);
    }
    
    $subtitle_length = $subtile_max_time - $subtile_min_time;

    print "Video Length $video_length sec\n" if($debug);
    print "Subtitles Length $subtitle_length sec\n" if($debug);

    #Check if the length is within tolerance
    return 1 if($subtitle_length == $video_length);
    return 1 if(($subtitle_length > $video_length) and ($subtitle_length <= $video_length + $vid_length_tol));
    return 1 if(($subtitle_length < $video_length) and ($subtitle_length + $vid_length_tol >= $video_length));

    #Otherwise die
    die "Length of video differs from length of GPS data. Cannot continue!\n";
}

###############################################################################
#Subroutine that converts GPS date/time into epoch
#Time example: 171140.50 <- 5:11:40.5PM
#Date example: 220812 <- 22/08/2012
#Note input is in UTC time
###############################################################################
sub timeToEpoch($$){
    (my $time, my $date) = @_;

    my $hour = substr($time,0,2);
    my $min = substr($time,2,2);
    my $sec = substr($time,4,2);
    my $part_sec = substr($time,6,2);
    my $mday = substr($date,0,2);
    my $mon = (substr($date,2,2) - 1);
    my $year = substr($date,4,2);
        
    return timegm($sec,$min,$hour,$mday,$mon,$year) + $part_sec;
}

###############################################################################
#Subroutine to generate the subtitles file using ffmpeg
###############################################################################
sub createSubs(){

	my $process_name = "Extracting GPS data from video";
	progress($process_name, 0);
	#system("ffmpeg -i $video_file -an -vn -sbsf mov2textsub -scodec copy -f rawvideo $subs_file");
	my @output = `ffmpeg -loglevel info -i $video_file -an -vn -scodec copy -f rawvideo $subs_file 2>&1`;
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
##############################################################################
sub readSubs(){

	my $process_name = "Reading GPS data";
	progress($process_name, 0);

    #These values are for filling in the missing dates. First value is the line#.
    my @smallest_GPS_time = (0,9999999999);
    my @largest_GPS_time = (0,-1);
    my @first_date;
    my @second_date;
    
    my %missing_times = ();
    my %missing_dates = ();
    my %epoch_lookup = (); #This is used when doing the second fill

    #Create a epoch lookup for all the times in the subs file
    my $line_num = 0;
    my $GPRMC_num = 0;
    my $line;
    open FILE, $subs_file or die $!;
    while ($line = <FILE>) {
        $line_num++;
        
        #Remove non printable characters
        $line =~ s/[[:^print:]]+//g;

        #Check that the line is valid
        my $gps_checksum = validateGpsChecksum($line);
        if($gps_checksum eq -1) {
            #The GPRMC string contains the date stamp
            if ($line =~ /\$GPRMC,(\d+(\.\d+)?),\w*,[0-9.]*,\w*,[0-9.]*,\w*,[0-9.]*,[0-9.]*,(\d*),/) {
                my $time = $1;
                my $date = $3;
                $GPRMC_num++;
                if( length($date) != 6 ) {
                    #We need to record that the date is missing
                    $missing_dates{ $time } = $line_num;
                } else {
                    my $epoch_time = timeToEpoch($time, $date);
                    $epoch_lookup{$time} = $epoch_time;

                    #If this is the first/second date we should record it for later
                    if(!@first_date) {
                        @first_date = ($line_num,$date,$GPRMC_num,$epoch_time);
                    }elsif(!@second_date) {
                        @second_date = ($line_num,$date,$GPRMC_num,$epoch_time);
                    }
                }

                #We also want to keep track of the largest/smallest GPS time
                if( $time > $largest_GPS_time[1]) {
                    @largest_GPS_time = ($line_num,$time);
                }
                if( $time < $smallest_GPS_time[1]) {
                    @smallest_GPS_time = ($line_num,$time);
                }
            }elsif($line =~ /\$GPRMC,,\w*,[0-9.]*,\w*,[0-9.]*,\w*,[0-9.]*,[0-9.]*,(\d*),/){
                $GPRMC_num++;
                #Record any missing times with a fake epoch, we will fill this in later
                $missing_times{ $GPRMC_num } = -1;
            }
            #We also need to check that the GPGGA data has a epoch time created. This assumes the GPRMC data preceeds the GPGGA data!
            if ($line =~ /\$GPGGA,(\d+(\.\d+)?),/) {
                my $time = $1;
                if(!exists($epoch_lookup{$time})){
                    $missing_dates{ $time } = $line_num;
                }
            }
        }
    }

    #Now we need to fill in any missing dates
    progress($process_name, 40);
    
    #Check that we have at least one date
    die "\n\nNo valid dates found in GPS data, Cannot continue!\nThis is probably due to no GPS fix\n" if(!@first_date);

    #The GPS period also used elsewhere so lets calculate this now
    $GPS_period = $second_date[3] - $first_date[3];

    if(%missing_times) {
        #This can be done reasonably easily as the time doesnt seem to disappear when GPS is lost (date does)
        foreach my $line (sort keys %missing_times){
            my $epoch_time = $first_date[3] + (($line - $first_date[2]) * $GPS_period);
            $missing_times{$line} = $epoch_time;
        }
    }

    if(%missing_dates) {
        #Determine if the video spans over UTC midnight.
        #To do this just check if the largest and smallest dates are close to midnight (within an hour)
        if( ($largest_GPS_time[1] > 230000) and ($smallest_GPS_time[1] < 10000) ) {
            print "\nVideo spans over UTC midnight\n" if($debug);
            #....TODO!!
            die "Havent fixed this yet";
        } else {
            #Since the video does not span midnight all dates will be the same.
            foreach my $time (keys %missing_dates){
                #First lets calculate the date
                my $epoch_time = timeToEpoch($time, $first_date[1]);
                $epoch_lookup{$time} = $epoch_time;
            }
        }
    }

    #Now that we have all the times in epoch we can read in the data
    progress($process_name, 60);

	#These should be all the vars that the contour GPS outputs.... (with reference to above)
	my ( $time, $lat, $latNS, $long, $longEW, $fixStatus, $validity, $numSat, $HDOP, $altitude, $geoidalSeparation, $speed, $trueCourse, $date ); 
    #Reset the file back to the begining
    seek(FILE,0,0) or die $!;
    $line_num = 0;    
    $GPRMC_num = 0;    
    my $GPGGA_num = 0;    
	open SUBS_GPGGA, '>', $save_subs_GPGGA_file or die $! if($save_subs);
	open SUBS_GPRMC, '>', $save_subs_GPRMC_file or die $! if($save_subs);
	while ($line = <FILE>) {
		$line_num++;
		#Remove non printable characters
		$line =~ s/[[:^print:]]+//g;

		#Check that the line is valid
        my $gps_checksum = validateGpsChecksum($line);
		if($gps_checksum eq -1) {
			#Separate GPRMC and GPGGA data
			if ($line =~ /GPGGA,(.+)/) {
				#We only care about the info after the GPGGA
				$line=$1;
			    ($time, $lat, $latNS, $long, $longEW, $fixStatus, $numSat, $HDOP, $altitude, $geoidalSeparation) = split(/,/, $line);
			
                $GPGGA_num++;

                #Grab epoch time from lookup hash
                my $epoch_time = $epoch_lookup{$time};

                #If there is no epoch time have a look in the missing_times hash
                if(!defined($epoch_time)){
                    if(defined($missing_times{ $GPGGA_num })){
                        $epoch_time = $missing_times{ $GPGGA_num };
                    }else{
                        die "\nEpoch time for $time not defined!?! On line# $line_num of subs file.\n";
                    }
                }

                addGPSData($epoch_time, 'time', $time);
                addGPSData($epoch_time, 'lat', $lat);
                addGPSData($epoch_time, 'latNS', $latNS);
                addGPSData($epoch_time, 'long', $long);
                addGPSData($epoch_time, 'longEW', $longEW);
                addGPSData($epoch_time, 'fixStatus', $fixStatus);
                addGPSData($epoch_time, 'numSat', $numSat);
                addGPSData($epoch_time, 'HDOP', $HDOP);
                addGPSData($epoch_time, 'altitude', $altitude);
                addGPSData($epoch_time, 'geoidalSeparation', $geoidalSeparation);
                addGPSData($epoch_time, 'lineNum', $line_num);
                
	    		#Also print these out to $savesubsfile if savesubs is set
	    		print SUBS_GPGGA "\$GPGGA,$line\n" if($save_subs);
		    }

    		if ($line =~ /GPRMC,(.+)/) {
    			#We only care about the info after the GPRMC
    			$line=$1;
    			($time, $validity, $lat, $latNS, $long, $longEW, $speed, $trueCourse, $date) = split(/,/, $line);

                $GPRMC_num++;

                #Grab epoch time from lookup hash
                my $epoch_time = $epoch_lookup{$time};

                #If there is no epoch time have a look in the missing_times hash
                if(!defined($epoch_time)){
                    if(defined($missing_times{ $GPRMC_num })){
                        $epoch_time = $missing_times{ $GPRMC_num };
                    }else{
                        die "\nEpoch time for $time not defined!?! On line# $line_num of subs file.\n";
                    }
                }

                addGPSData($epoch_time, 'time', $time);
                addGPSData($epoch_time, 'validity', $validity);
                addGPSData($epoch_time, 'lat', $lat);
                addGPSData($epoch_time, 'latNS', $latNS);
                addGPSData($epoch_time, 'long', $long);
                addGPSData($epoch_time, 'longEW', $longEW);
                addGPSData($epoch_time, 'speed', $speed);
                addGPSData($epoch_time, 'trueCourse', $trueCourse);
                addGPSData($epoch_time, 'date', $date);
                addGPSData($epoch_time, 'lineNum', $line_num);

    			#Also print these out to $savesubsfile if savesubs is set
    			print SUBS_GPRMC "\$GPRMC,$line,$epoch_time\n" if($save_subs);
    		}
    	}elsif($gps_checksum ne -2){
            #Report on checksums that have failed (not lines that dont match the regex...)
            $GPS_checksum_error{ $line_num } = $gps_checksum;
        }
    }
	close FILE or die $!;
	close SUBS_GPGGA or die $! if($save_subs);
	close SUBS_GPRMC or die $! if($save_subs);
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
#1) epoch timestamp
#2) var that is to be updated, eg: 'speed'
#3) value that should be stored
#Returns 1 on success, 2 if the value already exists
###############################################################################
sub addGPSData($$$) {
    (my $epoch, my $var, my $value) = @_;
    return 2 if(exists($GPS_data{ $epoch }{ $var }));
    $GPS_data{ $epoch }{ $var } = $value;
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

################################################################################
#NMEA GPS info
################################################################################
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