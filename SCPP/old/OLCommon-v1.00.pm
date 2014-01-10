#This module contains all routines that are shared by the overlay creation modules
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 26/04/13 First version as perl module
#
###############################################################################

package SCPP::Overlay::OLCommon; 
use strict;
use warnings;
use GD;
use SCPP::Config qw(:debug);

BEGIN {
    require Exporter;
    our $VERSION = 1.00;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(printString);
    our @EXPORT_OK = qw();
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
    print STDERR "Epoch_ID: $epoch, $type string $string is too long! Actual: $textLen[2] pixels, Max: $max_len pixels.\n" if(($textLen[2] > $max_len) and $print_err);

    #Calculate the offset based on the string length (Right justifying the text)
    $x = ($max_len - $textLen[2] + $x) if($justify == 1);

    #Print the string
    ${$im_ref}->stringFT($colour, $font, $size, 0, $x, $y, $string);
}

1;
