#!/usr/bin/perl -w
#Script to help add GPS related info to videos taken with a contour GPS camera
#
#Requires the following packages if you are using ubuntu:
# *libgd-gd2-perl
#Paul Johnston
###############################################################################
# History
###############################################################################
# 0.1  PJ 23/08/12 Original script
# 0.2  PJ 28/01/13 Added data validation
# 0.3  PJ 28/01/13 Fixed a few bugs removed old code
# 0.4  PJ 28/01/13 Fixed a few bugs added ability to fill in missing times
#
###############################################################################


use strict;
use Time::Local;
#use Time::HiRes;
use POSIX qw(strftime);
use GD;

my $save_subs = 1;
my $save_subs_GPGGA_file = "subs-GPGGA.txt";
my $save_subs_GPRMC_file = "subs-GPRMC.txt";

#Some Fonts
my $ubuntufont='/usr/share/fonts/truetype/ubuntu-font-family/Ubuntu-B.ttf';
my $ubuntuCfont='/usr/share/fonts/truetype/ubuntu-font-family/Ubuntu-C.ttf';
my $sansfont='/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans-Bold.ttf';

my $baseImageRes=720;
my $res=$baseImageRes / 720; #All dimensions are based off 720p res
my $knots2speed = 1.852; #Conversion from knots to km/h
my $vid_length_tol=2;
my $tmpdir="/tmp/contour_auth_$$/";
my $subs_file = "/tmp/contour_auth_subs.$$";
my $video_length;
my %GPS_data = (); #Hash of hashes to store GPS data
my %GPS_checksum_error = (); #Hash to store any GPS checksum errors 
my %GPS_date_error = (); #Hash to store any GPS date errors 
my $debug = 1;
$| = 1; #Disable buffering of stdout


sub createSubs();
sub readSubs();
sub progress($$);
sub validateGpsChecksum($);
sub errorReport();
sub timeToEpoch($$);
sub checkLength();

sub test();

###############################################################################
#Read in command line arguments
###############################################################################
die "You must specify a input file\n" if($#ARGV != 0);
my $video_file = $ARGV[0];

###############################################################################
#Main Program
###############################################################################

createSubs();
readSubs();
#We can now remove the temp subs file if there are no errors
unlink($subs_file) or die $! if(!%GPS_checksum_error);

checkLength();





test();

        
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
    
    my $subtitle_length = $subtile_max_time - $subtile_min_time;

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
	progress($process_name, 95);
    foreach my $line (@output) {
        if( $line =~ /Duration: (\d\d):(\d\d):(\d\d(\.\d*)?), start: /){
            $video_length = $3 + ( ($2 + ( $1 * 60 )) * 60 );
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

    if(%missing_times) {
        #This can be done reasonably easily as the time doesnt seem to disappear when GPS is lost (date does)
        my $GPS_freq = $second_date[3] - $first_date[3];
        foreach my $line (sort keys %missing_times){
            my $epoch_time = $first_date[3] + (($line - $first_date[2]) * $GPS_freq);
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
