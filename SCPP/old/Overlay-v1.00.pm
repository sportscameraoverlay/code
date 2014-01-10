#This module is used to various create video overlays
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 26/04/13 First version as perl module
#
###############################################################################

package SCPP::Overlay; 
use strict;
use warnings;
use GD;
use SCPP::Common;
use SCPP::Overlay::Digital;
use SCPP::Overlay::Speedo;
use SCPP::Config qw(:debug :tmp :overlay);

BEGIN {
    require Exporter;
    our $VERSION = 1.00;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(generateOverlays);
    our @EXPORT_OK = qw();
}

my $invalid_alt = "----";
my $invalid_speed = "---";
my $invalid_time = -1;
my $knots2speed = 1.852; #Conversion from knots to km/h

sub generateOverlays($$$$$);
sub positionImage($$$$$$$);

##############################################################################
#Main routine to Generate image overlays
#Requires the following:
#1) A reference to the GPS data hash
#2) The GPS period

#4) The (X) size to create the overlay
#5) The (Y) size to create the overlay

#8)
##############################################################################
sub generateOverlays($$$$$){
    my @overlay_res;
    (my $GPS_data_ref, my $GPS_period, $overlay_res[0], $overlay_res[1], my $length) = @_;

    my $process_name = "Creating overlay images";
    progress($process_name, 0);

    print "Images per sec: $images_per_sec\n" if($debug);
    print "GPS Period: $GPS_period\n" if($debug);
   
    #Calculate the number of images that need to be generated for each GPS reading (for interpolation of speed data)
    my $num_interpolated_pts = $images_per_sec * $GPS_period;
    my $num_of_images = $length * $images_per_sec; #Number of images for progess display

    my $image_num = 0; #We have to use this as melt cant deal with any missing numbers in a sequence
    my $maxspeed = 0;
    foreach my $GPSline (sort {$a <=> $b} keys %{$GPS_data_ref}){
        #Set the altitude and speed to defaults
        my $altitude = $invalid_alt;
        my $speed = $invalid_speed;
        my $time = $invalid_time;

        $altitude = ${$GPS_data_ref}{$GPSline}{'altitude'} if(defined(${$GPS_data_ref}{$GPSline}{'altitude'}) and ${$GPS_data_ref}{$GPSline}{'altitude'} =~ /^\d+(\.\d+)?$/);
        $speed = ${$GPS_data_ref}{$GPSline}{'speed'} * $knots2speed if(defined(${$GPS_data_ref}{$GPSline}{'speed'}) and ${$GPS_data_ref}{$GPSline}{'speed'} =~ /^\d+(\.\d+)?$/);
        $time = ${$GPS_data_ref}{$GPSline}{'epoch'} if(defined(${$GPS_data_ref}{$GPSline}{'epoch'}));
        
#        my $current_speed = $speed;
        my $next_speed;
        print "\nGPS Data line#: $GPSline\n" if($debug > 1);
        print "Epoch Time: $time\n" if($debug > 1);
        print "Current_speed: $speed\n" if($debug > 1);

        #Set the speed in the future to interpolate to
        if(defined(${$GPS_data_ref}{($GPSline + 1)}{'speed'}) and ${$GPS_data_ref}{($GPSline + 1)}{'speed'} =~ /^\d+(\.\d+)?$/){
            $next_speed = ${$GPS_data_ref}{($GPSline + 1)}{'speed'} * $knots2speed;
        }else{
            $next_speed = $speed;
        }
        print "Next Speed: $next_speed\n" if($debug > 1);
        #Determine the amount to increase the speed by set to undef if not valid
        my $speed_inc;
        if(($speed ne $invalid_speed) and ($next_speed ne $invalid_speed)){
            $speed_inc = ($next_speed - $speed) / $num_interpolated_pts;
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

            #Update maxspeed if the current speed is larger (and valid)
            if(($current_speed ne $invalid_speed)  and ($current_speed > $maxspeed)){
                $maxspeed = $current_speed;
            }
        
            #Create the overlays for the digital type
            $bim = digital($altitude, $current_speed, $maxspeed, $time) if($overlay_type eq 'digital');

            #Create the overlays for the speedo type
            $bim = speedo($altitude, $current_speed, $maxspeed, $time) if($overlay_type eq 'speedo');
       
            #Place the overlay in the right position/size
            positionImage($bim, $overlay_pos[0], $overlay_pos[1], $overlay_size, $image_num, $overlay_res[0], $overlay_res[1]);
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
#6)Original video res (X)
#7)Original video res (X)
#8)Temp dir path
##############################################################################
sub positionImage($$$$$$$){

    my @orig_vid_res;
    (my $bim, my $x_pos, my $y_pos, my $size, my $num, $orig_vid_res[0], $orig_vid_res[1]) = @_;

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
    my $full_image_name = $tmp_dir . '/contour_img-' . $num . '.png';
    open IMAGE, ">", $full_image_name or die $!;
    binmode IMAGE;
    print IMAGE $im->png;
    close IMAGE or die $!;
}

1;
