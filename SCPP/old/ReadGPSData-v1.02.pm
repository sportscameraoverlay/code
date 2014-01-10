#This module is used to read in the GPS data so it can be processed
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 26/04/13 First version as perl module
# 1.01  PJ 05/05/13 Updated debug output
# 1.02  PJ 16/06/13 Added subroutine to check and fill in missing GPS data (lat/long)
#
###############################################################################

package SCPP::ReadGPSData; 
use strict;
use warnings;
use Time::Local;
use SCPP::Common;
use SCPP::Config qw(:debug :tmp :video);

BEGIN {
    require Exporter;
    our $VERSION = 1.02;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(createSubs readGPSfile checkGPSData checkGPSPoints);
    our @EXPORT_OK = qw();
}

my $save_subs_GPGGA_file = "subs-GPGGA.txt";
my $save_subs_GPRMC_file = "subs-GPRMC.txt";

#Subroutines in this module:
sub createSubs($$);
sub readGPSfile($$);
sub validateGpsChecksum($);
sub timeToEpoch($$);
sub checkGPSData($$$);
sub addGPSData($$$$);
sub checkGPSPoints($);
###############################################################################
#Subroutine to generate the subtitles file using ffmpeg
#Requires the following:
#1) A video file to read 
#2) A file to save the subtitles to
#Returns the following:
#1) The video length
#2) The resolution of the video (X)
#3) The resolution of the video (Y)
#4) The bitrate of the video
#5) The framerate of the video
###############################################################################
sub createSubs($$){
    (my $video_file, my $subs_file) = @_;

	my $process_name = "Extracting GPS data from video";
    print "$process_name...\n" if($debug); 
	progress($process_name, 0);

    my $cmd = "ffmpeg -loglevel info -i \'$video_file\' -vn -an -scodec copy -f rawvideo $subs_file 2>&1";
    print "SYS_CMD: $cmd\n" if($debug > 1);
	my @output = `$cmd`;
	my $exitstatus = $? >> 8;
	die "\nFFMPEG failed with exitcode: $exitstatus\n\n@output\n" if( $exitstatus != 0 );
    print "@output\n" if($debug > 3);

    #Grab info about the video
    my ($video_length, @res, $bitrate, $framerate);
	progress($process_name, 90);
    foreach my $line (@output) {
        if( $line =~ /Duration: (\d\d):(\d\d):(\d\d(\.\d*)?), start: /){
            $video_length = $3 + ( ($2 + ( $1 * 60 )) * 60 );
        }
        #Stream #0:0(eng): Video: h264 (Main) (avc1 / 0x31637661), yuv420p, 1280x720 [SAR 1:1 DAR 16:9], 5231 kb/s, 25 fps, 25 tbr, 180k tbn, 50 tbc
        if( $line =~ /Stream #0.* Video: .+, .+, (\d+)x(\d+).*, (\d+(.\d+)?) kb\/s, (\d+(.\d+)?) fps,/){
            @res = ($1,$2);
            $bitrate = $3;
            $framerate = $5;
        }
    }
	progress($process_name, 100);
    return($video_length, @res, $bitrate, $framerate);
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
sub readGPSfile($$){
    (my $GPS_data_ref, my $file) = @_;

	my $process_name = "Reading GPS data";
    print "$process_name...\n" if($debug); 
	progress($process_name, 0);

    my ( @first_date , @second_date, @third_date );
    my $GPS_period;
    my $subs_file_err; #Gets set if we encouter an error
	#These should be all the vars that the contour GPS outputs....
	my ( $time, $lat, $latNS, $long, $longEW, $fixStatus, $validity, $numSat, $HDOP, $altitude, $geoidalSeparation, $speed, $trueCourse, $date ); 

    my $line_num = 0; #line number in the subtitles file (used for debug if anything fails later)
    my $GPSline = 0; #Incremented for every occurance of GPRMC data found and used in the GPSdata hash as the key
    my $line;
    open SUBS_GPGGA, '>', $save_subs_GPGGA_file or die $! if($save_subs);
    open SUBS_GPRMC, '>', $save_subs_GPRMC_file or die $! if($save_subs);
    open FILE, $file or die $!;
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
                print "A" if($debug > 2);
				#We only care about the info after the GPGGA
				$line=$1;
			    ($time, $lat, $latNS, $long, $longEW, $fixStatus, $numSat, $HDOP, $altitude, $geoidalSeparation) = split(/,/, $line);
			
                addGPSData($GPSline, 'time', $time, $GPS_data_ref);
                addGPSData($GPSline, 'lat', $lat, $GPS_data_ref);
                addGPSData($GPSline, 'latNS', $latNS, $GPS_data_ref);
                addGPSData($GPSline, 'long', $long, $GPS_data_ref);
                addGPSData($GPSline, 'longEW', $longEW, $GPS_data_ref);
                addGPSData($GPSline, 'fixStatus', $fixStatus, $GPS_data_ref);
                addGPSData($GPSline, 'numSat', $numSat, $GPS_data_ref);
                addGPSData($GPSline, 'HDOP', $HDOP, $GPS_data_ref);
                addGPSData($GPSline, 'altitude', $altitude, $GPS_data_ref);
                addGPSData($GPSline, 'geoidalSeparation', $geoidalSeparation, $GPS_data_ref);
                addGPSData($GPSline, 'lineNum', $line_num, $GPS_data_ref);
                
	    		#Also print these out to $savesubsfile if savesubs is set
	    		print SUBS_GPGGA "\$GPGGA,$line\n" if($save_subs);
		    }

    		if ($line =~ /GPRMC,(.+)/) {
                print "R" if($debug > 2);
    			#We only care about the info after the GPRMC
    			$line=$1;
    			($time, $validity, $lat, $latNS, $long, $longEW, $speed, $trueCourse, $date) = split(/,/, $line);

                addGPSData($GPSline, 'time', $time, $GPS_data_ref);
                addGPSData($GPSline, 'validity', $validity, $GPS_data_ref);
                addGPSData($GPSline, 'lat', $lat, $GPS_data_ref);
                addGPSData($GPSline, 'latNS', $latNS, $GPS_data_ref);
                addGPSData($GPSline, 'long', $long, $GPS_data_ref);
                addGPSData($GPSline, 'longEW', $longEW, $GPS_data_ref);
                addGPSData($GPSline, 'speed', $speed, $GPS_data_ref);
                addGPSData($GPSline, 'trueCourse', $trueCourse, $GPS_data_ref);
                addGPSData($GPSline, 'date', $date, $GPS_data_ref);
                addGPSData($GPSline, 'lineNum', $line_num, $GPS_data_ref);

                #Add the epoch time to the GPSdata hash (-1 if either time or date are invalid)
                my $epoch_time = timeToEpoch($time, $date);
                print "Date/time is invalid on line $GPSline\n" if($epoch_time == -1 and $debug > 1);
                addGPSData($GPSline, 'epoch', $epoch_time, $GPS_data_ref);

                #We need to calculate the GPS period as this is quite important later on
                if($epoch_time != -1){
                    if(!@first_date) {
                        @first_date = ($GPSline,$epoch_time,$line_num);
                        print "First Date: @first_date\n" if($debug > 2);
                    }elsif(!@second_date) {
                        @second_date = ($GPSline,$epoch_time,$line_num);
                        print "Second Date: @second_date\n" if($debug > 2);
                    }elsif(!@third_date) {
                        @third_date = ($GPSline,$epoch_time,$line_num);
                        print "Third Date: @third_date\n" if($debug > 2);
                        
                        #Once we have three dates check that they are in order and the GPS period is consistant otherwise undef them and try again
                        $GPS_period = $second_date[1] - $first_date[1];
                        print "GPS_period: $GPS_period\n" if($debug > 2);
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
            print STDERR "GPS checksum on line $line_num of the subs file did not match. Actual checksum $gps_checksum\n";
            $subs_file_err = 1;
        }
        print "." if($debug);
    }
    print "\n" if($debug);
	close FILE or die $!;
	close SUBS_GPGGA or die $! if($save_subs);
	close SUBS_GPRMC or die $! if($save_subs);

    #Check that we have successfully calculated the GPS_period otherwise there is no point continuing!
    die "\n\nNo valid dates found in GPS data, Cannot continue!\nThis is probably due to no GPS fix\n" if(!$GPS_period);
	
    progress($process_name, 100);

    #return the GPS period and any errors
    return ($GPS_period, $subs_file_err);
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
#Must recieve 4 values
#1) GPS data line number
#2) var that is to be updated, eg: 'speed'
#3) value that should be stored
#4) A reference to the GPS_data hash
#Returns 1 on success, 2 if the value already exists
###############################################################################
sub addGPSData($$$$) {
    (my $line, my $var, my $value, my $GPS_data_ref) = @_;
    return 2 if(exists(${$GPS_data_ref}{ $line }{ $var }));
    ${$GPS_data_ref}{ $line }{ $var } = $value;
    return 1;
}

##############################################################################
#Check that the length of the video is the same as the length of the subtitles
#Requires the following:
#1) A reference to the GPS_data hash to check 
#2) The video length to check against
#3) The period between subtitles
#Returns the length of the subtitles 
##############################################################################
sub checkGPSData($$$){
    (my $GPS_data_ref, my $video_length, my $GPS_period) = @_;

    my $subtitle_length;
    #First remove any duplicate times
    my %dup_times_check = ();
    foreach my $GPSline (sort keys %{$GPS_data_ref}){
        my $epoch_time = ${$GPS_data_ref}{ $GPSline }{ epoch };
        #We can only check for the dates that we have
        if(defined($epoch_time) and $epoch_time != -1){
            if(defined($dup_times_check{ $epoch_time })){
                print STDERR "Duplicate time $epoch_time: Line $dup_times_check{$epoch_time} and line ${$GPS_data_ref}{$GPSline}{line_num}.\n" if($print_err);
                delete ${$GPS_data_ref}{ $GPSline };
            }else{
                $dup_times_check{$epoch_time} = ${$GPS_data_ref}{$GPSline}{line_num};
            }
        }
    }

    #Calculate the length (time) of the subtitles
    my $GPS_data_lines = keys %{$GPS_data_ref};
    $subtitle_length = $GPS_data_lines * $GPS_period;

    print "Video Length $video_length sec\n" if($debug);
    print "Subtitles Length $subtitle_length sec\n" if($debug);

    #Check if the length is within tolerance
    return $subtitle_length if($subtitle_length == $video_length);
    return $subtitle_length if(($subtitle_length > $video_length) and ($subtitle_length <= $video_length + $vid_length_tol));
    return $subtitle_length if(($subtitle_length < $video_length) and ($subtitle_length + $vid_length_tol >= $video_length));

    #Otherwise die
    die "Length of video differs from length of GPS data by " . ($video_length - $subtitle_length) . "sec. Not proceeding! (Change vid_length_tol if this is ok)!\n";
}

###############################################################################
#Subroutine that converts GPS date/time into epoch
#Time example: 171140.50 <- 5:11:40.5PM
#Date example: 220812 <- 22/08/2012
#Note input is in UTC time
#Requires a time and a date in the above format
#Returns the epoch value
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
# Subroutine to check the GPS lat and long and fill in any missing points
###############################################################################
sub checkGPSPoints($){
    (my $GPS_data_ref) = @_;

    my $first_GPS_point;
    my $last_GPS_point;
    #First convert all valid GPS points into decimal notation and store in the GPS_data hash
    foreach my $GPSline (sort keys %{$GPS_data_ref}){
        if((${$GPS_data_ref}{$GPSline}{fixStatus} > 0) or (${$GPS_data_ref}{$GPSline}{validity} eq 'A')){
            my $NMEA_lat = ${$GPS_data_ref}{ $line }{'lat'};
            my $NMEA_long = ${$GPS_data_ref}{ $line }{'long'};
            if((${$GPS_data_ref}{ $line }{'latNS'} =~ /[NSns]/) and (${$GPS_data_ref}{ $line }{'longEW'} =~ /[EWew]/)){
                if($NMEA_lat =~ /(\d+)(\d\d\.\d+)/){
                    my $decimal_lat = $1 + ($2 / 60);
                    $decimal_lat = $decimal_lat * -1 if(${$GPS_data_ref}{ $line }{'latNS'} =~ /s/i);
                    if($NMEA_long =~ /(\d+)(\d\d\.\d+)/){
                        my $decimal_long = $1 + ($2 / 60);
                        $decimal_long = $decimal_long * -1 if(${$GPS_data_ref}{ $line }{'longEW'} =~ /w/i);
                        #If all is well store the points in the GPS_data hash
                        addGPSData($GPSline, 'decimal_lat', $decimal_lat, $GPS_data_ref);
                        addGPSData($GPSline, 'decimal_long', $decimal_long, $GPS_data_ref);
                        next;
                    }
                }
            }
        }
        print "$GPSline has invalid GPS data\n" if($debug > 1);
    }


    #Then we need to find the First and last reliable GPS points
    #First point
    foreach my $GPSline (sort keys %{$GPS_data_ref}){
        if(defined(${$GPS_data_ref}{$GPSline}{'decimal_lat'})){
            $first_GPS_point = $GPSline;
            print "First valid GPS point found on line $GPSline\n" if($debug > 1);
            last;
        }
    }
    #Last point
    foreach my $GPSline (sort {$b <=> $a} keys %{$GPS_data_ref}){
        if(defined(${$GPS_data_ref}{$GPSline}{'decimal_lat'})){
            $last_GPS_point = $GPSline;
            print "Last valid GPS point found on line $GPSline\n" if($debug > 1);
            last;
        }
    }

    #Now we need to loop through the GPS_data hash and fill in any missing values that were not valid above
    my $GPS_lines = keys %{$GPS_data_ref};
    for(my $GPSline = 1; $GPSline <= $GPS_lines; $GPSline++){
        #Count the number of missing values
        my $missing_line_count = 0;
        while(!defined(${$GPS_data_ref}{$GPSline + $missing_line_count}{'decimal_lat'})){
            $missing_line_count++;
        }
        #fix the missing data
        if($missing_line_count > 0){
            my $first_lat_pt;
            my $first_long_pt;
            my $lat_inc = 0;
            my $long_inc = 0;
            #If the first line we can't approximate yet so just set to the first known point
            if($GPSline == 1){
                $first_lat_pt = ${$GPS_data_ref}{$first_GPS_point}{'decimal_lat'};
                $first_long_pt = ${$GPS_data_ref}{$first_GPS_point}{'decimal_long'};
            }
            #If the last line we also can't approximate so just set to the last known point
            elsif(($GPSline + $missing_line_count - 1) == $GPS_lines){
                $first_lat_pt = ${$GPS_data_ref}{$last_GPS_point}{'decimal_lat'};
                $first_long_pt = ${$GPS_data_ref}{$last_GPS_point}{'decimal_long'};
            }
            #Otherwise interpolate between the known points
            else{
                $first_lat_pt = ${$GPS_data_ref}{$GPSline - 1}{'decimal_lat'};
                my $second_lat_pt = ${$GPS_data_ref}{$GPSline + $missing_line_count}{'decimal_lat'};
                $lat_inc = ($second_lat_pt - $first_lat_pt) / ($missing_line_count + 1);
                
                $first_long_pt = ${$GPS_data_ref}{$GPSline - 1}{'decimal_long'};
                my $second_long_pt = ${$GPS_data_ref}{$GPSline + $missing_line_count}{'decimal_long'};
                $long_inc = ($second_long_pt - $first_long_pt) / ($missing_line_count + 1);
            }
            #store the missing entries
            for(my $missing_pt = 0; $missing_pt < $missing_line_count; $missing_pt++){
                ${$GPS_data_ref}{$GPSline + $missing_pt}{'decimal_lat'} = $first_lat_pt + ($lat_inc * ($missing_pt + 1));
                ${$GPS_data_ref}{$GPSline + $missing_pt}{'decimal_long'} = $first_long_pt + ($long_inc * ($missing_pt + 1));
            }
        }

        #Skip lines we have already filled in
        $GPSline = $GPSline + $missing_line_count - 1;
    }

}
1;
