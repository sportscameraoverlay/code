#This module is used to create a KML tour based on data from the GPS_data hash
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 25/04/13 First version as perl module
#
###############################################################################

package SCPP::KmlGen;
use strict;
use warnings;
use XML::LibXML;
use SCPP::Config qw(:debug :tmp);

BEGIN {
    require Exporter;
    our $VERSION = 1.00;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(genKML);
    our @EXPORT_OK = qw();
}

#KML generation constants
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
my $kml_pos_marker_scale = "1";

sub latConv($$);
sub longConv($$);
###############################################################################
#Main Subroutine to generate a KML tour based on the GPS points
#Requires the following to be passed in:
#1) The GPS_data hash
#2) The name of the KML file to create
#3) The project name
#4) The GPS period
###############################################################################
sub genKML($$$$){

    (my $GPS_data_ref, my $kml_file, my $project_name, my $GPS_period) = @_;

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
	foreach my $GPSline (sort {$a <=> $b} keys %{$GPS_data_ref}){
        #print out track
		my $lat = latConv($GPSline, $GPS_data_ref);
		my $long = longConv($GPSline, $GPS_data_ref);
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
        $heading->appendTextNode(${$GPS_data_ref}{ $GPSline }{'trueCourse'});
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
	print "Writing KML to $kml_file\n" if($debug);
	open KML, '>', $kml_file or die $!;
	print KML $xml->toString($xml_format);
	close KML or die $!;
}


###############################################################################
#Convert Latitude from NMEA GPS format to Decimal format
#Requires the GPSdata line#
#Returns the lat decimal notation
###############################################################################
sub latConv($$){
        (my $line, my $GPS_data_ref) = @_;
        #NMEA format is DDMM.mmmm
	    my $NMEA_lat = ${$GPS_data_ref}{ $line }{'lat'};
        if($NMEA_lat =~ /(\d+)(\d\d\.\d+)/){
                my $decimal_lat = $1 + ($2 / 60);
                return 1001 if(!defined(${$GPS_data_ref}{ $line }{'latNS'}));
                $decimal_lat = $decimal_lat * -1 if(${$GPS_data_ref}{ $line }{'latNS'} =~ /s/i);
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
sub longConv($$){
        (my $line, my $GPS_data_ref) = @_;
        #NMEA format is DDMM.mmmm       
	my $NMEA_long = ${$GPS_data_ref}{ $line }{'long'};
        if($NMEA_long =~ /(\d+)(\d\d\.\d+)/){
	        my $decimal_long = $1 + ($2 / 60);
		return 1001 if(!defined(${$GPS_data_ref}{ $line }{'longEW'}));
        	$decimal_long = $decimal_long * -1 if(${$GPS_data_ref}{ $line }{'longEW'} =~ /w/i);
        	return $decimal_long;
	}else{
		return 1000;
	}
}
1;
