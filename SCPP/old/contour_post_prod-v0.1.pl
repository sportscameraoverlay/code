#!/usr/bin/perl -w
#Script to help add GPS related info to videos taken with a contour GPS camera
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 0.1  PJ 23/08/12 Original script
###############################################################################


use strict;
use Time::Local;
use POSIX qw(strftime);

my $video_file = "/home/paul/contour_auth/100MEDIA/FILE0007.MOV";
my $subs_file = "/tmp/contour_auth_subs.$$";
my $knots2speed = 1.852; #Conversion from knots to km/h
my %GPS_data = ();
$| = 1; #Disable buffering of stdout

sub createSubs();
sub readSubs();
sub timeData($$);

##############################################################################
#Main Program
##############################################################################

createSubs();
readSubs();
#We can now remove the temp subs file
#unlink($subs_file) or die $!;
foreach my $time (sort keys %GPS_data){
	 
	
	if ($GPS_data{ $time }{'fixStatus'} == 1){
		my $time_string = strftime "%a %b %e %H:%M:%S %Y", localtime(timeData($time, $GPS_data{ $time }{'date'}));
		my $speed = $knots2speed * $GPS_data{ $time }{'speed'};
		print "$time_string, $speed km/h\n";
	}
}

###############################################################################
#Subroutine that returns time/date data
#Time example: 171140.50 <- 5:11:40.5PM
#Date example: 220812 <- 22/08/2012
#Note input is in UTC time
###############################################################################
sub timeData($$){
	my ($utctime, $date) = @_;
#	return "Time Error" if(length($utctime) < 6);
#	return "Date Error" if(length($date) < 6);
	my $hour = substr($utctime,0,2);
	my $min = substr($utctime,2,2);
	my $sec = substr($utctime,4,2);
	my $mday = substr($date,0,2);
	my $mon = (substr($date,2,2) - 1);
	my $year = substr($date,4,2);
	return timegm($sec,$min,$hour,$mday,$mon,$year);
}

###############################################################################
#Subroutine to generate the subtitles file using ffmpeg
###############################################################################
sub createSubs(){

	print "Extracting GPS data from video...";
	system("ffmpeg -i $video_file -an -vn -sbsf mov2textsub -scodec copy -f rawvideo $subs_file");
	print "Done\n";
}

###############################################################################
#Subroutine to read the GPS data from the subtitles file generated but createSubs
#
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
###############################################################################
sub readSubs(){

	print "Reading GPS data";
	#These should be all the vars that the contour GPS outputs.... (with reference to above)
	my ( $time, $lat, $latNS, $long, $longEW, $fixStatus, $validity, $numSat, $HDOP, $altitude, $geoidalSeparation, $speed, $trueCourse, $date ); 
	my $line;	
	open FILE, $subs_file or die $!;
	while ($line = <FILE>) {
		chomp $line;
		#Separate GPRMC and GPGGA data
		if ($line =~ /GPGGA/) {
			(undef, $time, $lat, $latNS, $long, $longEW, $fixStatus, $numSat, $HDOP, $altitude, $geoidalSeparation) = split(/,/, $line);
			$GPS_data{ $time }{'lat'} = $lat;
			$GPS_data{ $time }{'latNS'} = $latNS;
			$GPS_data{ $time }{'long'} = $long;
			$GPS_data{ $time }{'longEW'} = $longEW;
			$GPS_data{ $time }{'fixStatus'} = $fixStatus;
			$GPS_data{ $time }{'numSat'} = $numSat;
			$GPS_data{ $time }{'HDOP'} = $HDOP;
			$GPS_data{ $time }{'altitude'} = $altitude;
			$GPS_data{ $time }{'geoidalSeparation'} = $geoidalSeparation;
#print "$time\n";
		}		
		if ($line =~ /GPRMC/) {
			(undef, $time, $validity, $lat, $latNS, $long, $longEW, $speed, $trueCourse, $date) = split(/,/, $line);
			$GPS_data{ $time }{'validity'} = $validity;
			$GPS_data{ $time }{'speed'} = $speed;
			$GPS_data{ $time }{'trueCourse'} = $trueCourse;
			$GPS_data{ $time }{'date'} = $date;
		}
		print ".";
	}
	close FILE or die $!;
	print "Done\n";
}
