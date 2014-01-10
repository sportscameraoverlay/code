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
# 0.2  PJ 26/01/13 Added data validation
# 0.3  PJ 23/08/12 Added Image creation
###############################################################################


use strict;
use Time::Local;
#use Time::HiRes;
use POSIX qw(strftime);
use GD;


my $video_file = "/home/paul/contour_auth/100MEDIA/FILE0007.MOV";
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
sub addTimeData();
sub progress($$);
sub validateGpsChecksum($);
sub errorReport();
sub timeToEpoch($$);

##############################################################################
#Main Program
##############################################################################

createSubs();
print "Video Length $video_length sec\n" if($debug);;
readSubs();
#We can now remove the temp subs file if there are no errors
unlink($subs_file) or die $! if(!%GPS_checksum_error);

#foreach my $time (sort keys %GPS_data){
#	if (defined($GPS_data{ $time }{'fixStatus'}) and ($GPS_data{ $time }{'fixStatus'} == 1)){
#print $time;	 
#print " $GPS_data{ $time }{'validity'} $GPS_data{ $time }{'fixStatus'} $GPS_data{ $time }{'date'}\n";	
#		my $time_string = strftime "%a %b %e %H:%M:%S %Y", localtime(timeData($time, $GPS_data{ $time }{'date'}));
#		my $speed = $knots2speed * $GPS_data{ $time }{'speed'};
		#print "$time_string, $speed km/h\n";
#	}
#}
errorReport();

##############################################################################
#Report on errors
##############################################################################
sub errorReport(){
    #Report on the checksum errors
    if(%GPS_checksum_error){
        print "The following lines of the extracted subtitles contain NMEA GPS checksums that don\'t match reality:\n";
        foreach my $fail_line (sort {$a <=> $b} keys(%GPS_checksum_error)){
            print "line $fail_line, actual checksum $GPS_checksum_error{$fail_line}\n";
        }
        print "The extracted subtitles file($subs_file) has been retained\n";
    }

    #Report on any date errors
#    if(%GPS_date_error){
#        print "The times did not have valid dates:\n";
#        foreach my $fail_line (sort {$a <=> $b} keys(%GPS_date_error)){
#            print "Timestamp $fail_line\n";
#        }
#        print "This may be due to missing/corrupt GPRMC data in the subtitle file (see above)\n";
#    }
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

#To delete
sub addTimeData(){
   	my $process_name = "Parsing and Fixing any missing dates";
	progress($process_name, 0);
	my @date_missing;
    foreach my $time (sort keys %GPS_data){
        if (defined($GPS_data{ $time }{'date'}) and (length($GPS_data{ $time }{'date'}) == 6)){
        	my $date = $GPS_data{ $time }{'date'};
        	my $hour = substr($time,0,2);
        	my $min = substr($time,2,2);
         	my $sec = substr($time,4,2);
            my $part_sec = substr($time,6,2);
        	my $mday = substr($date,0,2);
        	my $mon = (substr($date,2,2) - 1);
        	my $year = substr($date,4,2);
        
            #Now add the generated time to the GPS_data hash
            $GPS_data{ $time }{'epochTime'} = timegm($sec,$min,$hour,$mday,$mon,$year) + $part_sec;
        }else{
            push(@date_missing, $time);
        }
    }


    #Fix any Missing dates
    if(@date_missing){
	    progress($process_name, 50);
        
        #Find the start time so we can fill in missing dates below
        my $start_time;
        my $lowest_line_num = 9999999; #Just a large number.... nothing special
        my $date_before_midnight;
        my $date_after_midnight;
        my $largest_time_with_date = -1;
        foreach my $time (keys %GPS_data){
            if($GPS_data{ $time }{'lineNum'} < $lowest_line_num){
                $start_time = $time;
                $lowest_line_num = $GPS_data{ $time }{'lineNum'};
            }
            #We also want to find the largest time value with a date
            if(($time > $largest_time_with_date) and defined($GPS_data{ $time }{'date'}) and (length($GPS_data{ $time }{'date'}) == 6)){
                $date_before_midnight = $GPS_data{ $time }{'date'};
                $largest_time_with_date = $time;
            }
        }

        die "\nNo valid date string found in GPS info.\n There was probably no GPS fix\n" if($largest_time_with_date == -1);

        #Determine the start time in seconds past midnight
        my $hour = substr($start_time,0,2);
       	my $min = substr($start_time,2,2);
       	my $sec = substr($start_time,4,5);
        my $start_time_sec = ((($hour * 60 ) + $min ) * 60) + $sec;

        print "\nVideo start time (sec past midnight): $start_time_sec sec\n" if($debug);
        print "Date after UTC Midnight: $date_after_midnight\n" if($debug);

        #We also need the date

        #Add the start time to the video length and check if this is over midnight
        if($start_time_sec + $video_length >= 86400){
            print "Video spans over UTC midnight\n" if($debug);
            #if it is set the date after midnight
        }
        

    }

	progress($process_name, 100);
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
    my @smallest_GPS_time = 0,999999999;
    my @largest_GPS_time = 0,-1;
    my @first_date;
    
    my %missing_dates = ();
    my %epoch_lookup = (); #This is used when doing the second fill

    #Create a epoch lookup for all the times in the subs file
    my $line_num = 0;
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
            if ($line =~ /\$GPRMC,(.+),.*,.*,.*,.*,.*,.*,.*,(.*),/) {
                my $time = $1;
                my $date = $2;
                if( length($date) != 6 ) {
                    #We need to record that the date is missing
                    $missing_dates{ $time } = $line_num;
                } else {
                    my $epoch_time = timeToEpoch($time, $date);
                    $epoch_lookup{$time} = $epoch_time;

                    #If this is the first date we should record it for later
                    if(!@first_date) {
                        @first_date = $line_num,$date; #This prob should be in epoch to save rework later?
                    }
                }

                #We also want to keep track of the largest/smallest GPS time
                if( $time > $largest_GPS_time[1]) {
                    @largest_GPS_time = $line_num,$time;
                }
                if( $time < $smallest_GPS_time[1]) {
                    @smallest_GPS_time = $line_num,$time;
                }
            }
            #We also need to check that the GPGGA data has a epoch time created. This assumes the GPRMC data preceeds the GPGGA data!
            if ($line =~ /\$GPGGA,(.+),/) {
                my $time = $1;
                if(!exists($epoch_lookup{$time}){
                    $missing_dates{ $time } = $line_num;
                }
            }
        }
    }

    #Now we need to fill in any missing dates
    progress($process_name, 40);

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
                my $epoch_time = timeToEpoch($time, $first_date);
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
			    
                #Grab epoch time from lookup hash
                my $epoch_time = $epoch_lookup{$time};

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
                addGPSData($epoch_time, 'lineNum', $lineNum);
                
	    		#Also print these out to $savesubsfile if savesubs is set
	    		print SUBS_GPGGA "\$GPGGA,$line\n" if($save_subs);
		    }

    		if ($line =~ /GPRMC,(.+)/) {
    			#We only care about the info after the GPRMC
    			$line=$1;
    			($time, $validity, $lat, $latNS, $long, $longEW, $speed, $trueCourse, $date) = split(/,/, $line);

                #Grab epoch time from lookup hash
                my $epoch_time = $epoch_lookup{$time};

                addGPSData($epoch_time, 'time', $time);
                addGPSData($epoch_time, 'validity', $validity);
                addGPSData($epoch_time, 'lat', $lat);
                addGPSData($epoch_time, 'latNS', $latNS);
                addGPSData($epoch_time, 'long', $long);
                addGPSData($epoch_time, 'longEW', $longEW);
                addGPSData($epoch_time, 'speed', $speed);
                addGPSData($epoch_time, 'trueCourse', $trueCourse);
                addGPSData($epoch_time, 'date', $date);
                addGPSData($epoch_time, 'lineNum', $lineNum);

    			#Also print these out to $savesubsfile if savesubs is set
    			print SUBS_GPRMC "\$GPRMC,$line\n" if($save_subs);
    		}
    	}else{
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

    $gps_string =~ /\$(.+)\*(..)/;
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
