#This module is used to print a digital overlay
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 26/04/13 First version as perl module
#
###############################################################################

package SCPP::Overlay::Digital; 
use strict;
use warnings;
use SCPP::Overlay::OLCommon;
use SCPP::Config qw(:debug :tmp :overlay :overlaysub);

BEGIN {
    require Exporter;
    our $VERSION = 1.00;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(digital);
    our @EXPORT_OK = qw();
}

#Whether to display fractions or not
my $frac = 1;

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

##############################################################################
#Subroutine digital
#This subroutine is used to create an overlay image with digital data for 
#altitude, max speed and current speed
#The following is passed in
#1)Altitude
#2)Speed
#3)Max Speed
#4)epoch time - not currently used
#And this sub returns a reference to the image created
##############################################################################
sub digital($$$$){
    (my $altitude, my $speed, my $maxspeed, my $epoch_time) = @_;
    
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
    if($maxspeed =~ /^\d+\.\d+$/){
        #Split the maxspeed vars into intergers and fractions
        $maxspeedInt = int($maxspeed);
        $maxspeedF = '.' . int(($maxspeed - $maxspeedInt) * 10);
    }else{
        $maxspeedInt = $maxspeed;
    }
    if($speed =~ /^\d+\.\d+$/){
        #Split the speed vars into intergers and fractions
        $speedInt = int($speed);
        $speedF = '.' . int(($speed - $speedInt) * 10);
    }else{
        $speedInt = $speed;
    }

    #Convert the altitude to an interger
    $altitude = int($altitude) if($altitude =~ /^\d+\.\d+$/);

    #Print the strings
    printString($text1,$font_normal,$text_sizeL,$altTextboxOff,$textHeight,$altitude,"Altitude",$altTextboxLen,$epoch_time,1,\$bim);
    printString($text1,$font_normal,$text_sizeL,$mspeedTextboxOff,$textHeight,$maxspeedInt,"Max_Speed",$mspeedTextboxLen,$epoch_time,1,\$bim);
    printString($text1,$font_normal,$text_sizeM,$mspeedFTextboxOff,$textHeight,$maxspeedF,"Max_Speed",$mspeedFTextboxLen,$epoch_time,0,\$bim) if(defined($maxspeedF));
    printString($text1,$font_normal,$text_sizeL,$speedTextboxOff,$textHeight,$speedInt,"Speed",$speedTextboxLen,$epoch_time,1,\$bim);
    printString($text1,$font_normal,$text_sizeM,$speedFTextboxOff,$textHeight,$speedF,"Speed_Fraction",$speedFTextboxLen,$epoch_time,0,\$bim) if(defined($speedF));

    #return a reference to the image created
    return \$bim;
}
1;
