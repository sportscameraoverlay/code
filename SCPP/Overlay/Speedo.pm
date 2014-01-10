#This module is used to enerate the speedo overlay
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 26/04/13 First version as perl module
#
###############################################################################

package SCPP::Overlay::Speedo; 
use strict;
use warnings;
use GD;
use SCPP::Overlay::OLCommon;
use SCPP::Config qw(:debug :tmp :overlay :overlaysub);

BEGIN {
    require Exporter;
    our $VERSION = 1.00;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(speedo);
    our @EXPORT_OK = qw();
}

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

##############################################################################
#Subroutine speedo
#This subroutine is used to create an overlay image of an analog speedo
#The following is passed in
#1)Altitude
#2)Speed
#3)Max Speed
#4)epoch time - not currently used
#And this sub returns a reference to the image created
##############################################################################
sub speedo($$$$){    
    (my $altitude, my $speed, my $maxspeed, my $epoch_time) = @_;
    
    print "Creating speedo overlay (Speedo.pm)\n" if($debug >2);
    #Draw the overlay text over the base image
    my $bim = GD::Image->trueColor(1);
    print "Base image file: $base_image_file\n" if($debug >3);
    $bim = newFromPng GD::Image($base_image_file);
    print "Base image file created...\n" if($debug >3);
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

    #Print the altitude in the centre
    $altitude = sprintf( '%04.0f', $altitude) if($altitude =~ /^[\d\.]+$/);
    my @altitude_chars = split(/ */, $altitude);
    for(my $i = 0; $i < 4; $i++){
        printString($text1,$font_normal,$speedo_alt_text_size,$speedo_altTextboxOff[$i],$speedo_textHeight,$altitude_chars[$i],"Altitude",$speedo_altTextboxLen,$epoch_time,0,\$bim);
    }

    #Print the current speed needle pos
    print_needle($speed_ang, $needle1, \$bim);

    #Print the max speed needle pos
    print_needle($mspeed_ang, $needle2, \$bim);
        
    #Lets also print some debug info if debug is set high enough
    if($debug and $debug > 3){ 
        printString($needle1,$font_normal,18,5,395,"Speed: $speed, Altitude: $altitude","Debug",395,$epoch_time,0,\$bim);
    }   

    #Fill in the centre of the speedo
    $bim->filledEllipse($speedo_centre[0],$speedo_centre[1],$speedo_centre_size,$speedo_centre_size,$black);

    return \$bim;
}

##############################################################################
#Subroutine to print needle position
#Requires an angle for the needle, a colour and the image reference
##############################################################################
sub print_needle($$$){
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

1;
