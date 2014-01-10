#This module is used to create a KML tour based on data from the GPS_data hash
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 25/04/13 First version as perl module
# 1.01  PJ 05/05/13 Updated debug output and added progress
# 1.02  PJ 09/06/13 Added start delay
# 1.03  PJ 19/07/13 Added skiruns and chairlifts to KML from a OSM file
#
###############################################################################

package SCPP::KmlGen;
use strict;
use warnings;
use XML::LibXML;
use Math::Trig qw(great_circle_distance deg2rad);
use SCPP::Config qw(:debug :tmp :kml);
use SCPP::Common;

BEGIN {
    require Exporter;
    our $VERSION = 1.02;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(genKML);
    our @EXPORT_OK = qw();
}

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

    my $process_name = "Creating KML tour file";
    print "$process_name...\n" if($debug);
    progress($process_name, 0);

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
        #print gx:labelVisibility
        my $gx_labelVisibility = $xml->createElement("gx:labelVisibility");
        $gx_labelVisibility->appendTextNode($kml_line_styles{$line_style}{'labelVisibility'});
        $linestyle_tag->appendChild($gx_labelVisibility);
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
    my $tessellate = $xml->createElement("tessellate");
    $tessellate->appendTextNode('1');
    $linestring->appendChild($tessellate);

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
    my $last_direction = 0; #Only used if direction smoothing is off
	foreach my $GPSline (sort {$a <=> $b} keys %{$GPS_data_ref}){
        print "Printing KML for line: $GPSline\n" if($debug > 2); 
        #print out track
        #my $lat = latConv($GPSline, $GPS_data_ref);
		my $lat = ${$GPS_data_ref}{ $GPSline }{'decimal_lat'};
        #my $long = longConv($GPSline, $GPS_data_ref);
		my $long = ${$GPS_data_ref}{ $GPSline }{'decimal_long'};
		$coordinates->appendTextNode("$long,$lat,0\n");

        #Create flyto elements
        my $gx_flyto =  $xml->createElement("gx:FlyTo");
        $gx_playlist->appendChild($gx_flyto);
        #flyto - duration
        my $gx_duration = $xml->createElement("gx:duration");
        if($GPSline == 1){
            $gx_duration->appendTextNode($ge_first_point_wait);
        }else{
            $gx_duration->appendTextNode($GPS_period);
        }
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
        if($smooth_direction){
            $heading->appendTextNode(${$GPS_data_ref}{ $GPSline }{'dir_roll_avg'});
        }elsif(defined(${$GPS_data_ref}{ $GPSline }{'trueCourse'})){
            $heading->appendTextNode(${$GPS_data_ref}{ $GPSline }{'trueCourse'});
            $last_direction = ${$GPS_data_ref}{ $GPSline }{'trueCourse'};
        }else{
            print "True Course not defined, using last direction at GPS line $GPSline\n" if($debug > 1); 
            $heading->appendTextNode($last_direction);
        }
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

    #If we have a map file lets parse it and add the tracks
    if($map_file){
        my %skiruns;
        parseMapData(\%skiruns);

        #First create a skiPOI Folder and close it by default
        my $folder_SR = $xml->createElement("Folder");
        $document->appendChild($folder_SR);
        my $name_SR = $xml->createElement("name");
        $name_SR->appendTextNode('ski POI');
        $folder_SR->appendChild($name_SR);
        my $open_SR = $xml->createElement("open");
        $open_SR->appendTextNode('0');
        $folder_SR->appendChild($open_SR);

        #Add skiruns/chairlifts to Placemarks
        foreach my $skirun (keys %skiruns){
            my $placemark_SR = $xml->createElement("Placemark");
            $folder_SR->appendChild($placemark_SR);
            my $track_name_SR = $xml->createElement("name");
            $track_name_SR->appendTextNode($skiruns{$skirun}{'name'});
            $placemark_SR->appendChild($track_name_SR);
            my $styleurl_SR = $xml->createElement("styleUrl");
            $styleurl_SR->appendTextNode($skiruns{$skirun}{'style'});
            $placemark_SR->appendChild($styleurl_SR);
            my $linestring_SR = $xml->createElement("LineString");
            $placemark_SR->appendChild($linestring_SR);
            my $tessellate_SR = $xml->createElement("tessellate");
            $tessellate_SR->appendTextNode('1');
            $linestring_SR->appendChild($tessellate_SR);
            my $coordinates_SR = $xml->createElement("coordinates");
            $linestring_SR->appendChild($coordinates_SR);
            foreach my $node_num (sort {$a <=> $b} keys $skiruns{$skirun}{'nodes'}){
                my @cur_loc = ($skiruns{$skirun}{'nodes'}{$node_num}{'lon'}, $skiruns{$skirun}{'nodes'}{$node_num}{'lat'});
                $coordinates_SR->appendTextNode("$cur_loc[0],$cur_loc[1],0\n");
                #Check if the distance between the current and next point (if there is one) is less than specified
                if(exists($skiruns{$skirun}{'nodes'}{$node_num + 1})){
                    my @next_loc = ($skiruns{$skirun}{'nodes'}{$node_num + 1}{'lon'}, $skiruns{$skirun}{'nodes'}{$node_num + 1}{'lat'});
                    #Calculate the distance
                    my $dist = great_circle_distance(deg2rad($cur_loc[0]), deg2rad($cur_loc[1]), deg2rad($next_loc[0]), deg2rad($next_loc[1]), $earths_radius);
                    if($dist > $min_kml_path_dist){
                        my $num_interpolated_pts = int($dist / $min_kml_path_dist);
                        my $next_node = $node_num + 1;
                        print "Distance($dist) is to long between points $node_num and $next_node for $skiruns{$skirun}{'name'}. Adding $num_interpolated_pts Points.\n" if($debug > 1);
                        my $long_inc = ($next_loc[0] - $cur_loc[0]) / $num_interpolated_pts;
                        my $lat_inc = ($next_loc[1] - $cur_loc[1]) / $num_interpolated_pts;
                        for( my $i = 1; $i < $num_interpolated_pts; $i++ ){
                            my $interpolated_long = $cur_loc[0] + ($long_inc * $i);
                            my $interpolated_lat = $cur_loc[1] + ($lat_inc * $i);
                            $coordinates_SR->appendTextNode("$interpolated_long,$interpolated_lat,0\n");
                        }
                    }
                }
            }
        }
    }

	$xml->setDocumentElement($kml);
	print "Writing KML to $kml_file\n" if($debug);
	open KML, '>', $kml_file or die $!;
	print KML $xml->toString($xml_format);
	close KML or die $!;

    progress($process_name, 100);
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
###############################################################################
#Subroutine to parse map data
###############################################################################
sub parseMapData($){
    (my $skiruns_ref) = @_;

    my $parser = XML::LibXML->new();
    my $xmldoc = $parser->parse_file($map_file);

    #First read the nodes (lat/long data) into a hash
    my %nodes;
    foreach my $node ($xmldoc->findnodes('/osm/node')){
        my $node_id = $node->getAttribute('id');
        $nodes{$node_id}{'lat'} = $node->getAttribute('lat');
        $nodes{$node_id}{'lon'} = $node->getAttribute('lon');
    }

    #Then build the skiruns hash
    foreach my $way ($xmldoc->findnodes('/osm/way')){
        my $way_id = $way->getAttribute('id');

        #Record all tag data about the way
        foreach my $tag ($way->findnodes('tag')){
            my $key = $tag->getAttribute('k');
            ${$skiruns_ref}{$way_id}{$key} = $tag->getAttribute('v');
        }

        #Record all node data about the way (populate from the %nodes hash)
        my $node_cnt = 1;
        foreach my $nd ($way->findnodes('nd')){
            my $node_ref = $nd->getAttribute('ref');
            ${$skiruns_ref}{$way_id}{'nodes'}{$node_cnt}{'node_id'} = $node_ref;
            ${$skiruns_ref}{$way_id}{'nodes'}{$node_cnt}{'lat'} = $nodes{$node_ref}{'lat'};
            ${$skiruns_ref}{$way_id}{'nodes'}{$node_cnt}{'lon'} = $nodes{$node_ref}{'lon'};
            $node_cnt++;
        }
    }

    foreach my $way (keys %{$skiruns_ref}){
        #Find all ways with "piste:type downhill"
        if(exists(${$skiruns_ref}{$way}{'piste:type'}) and (${$skiruns_ref}{$way}{'piste:type'} eq 'downhill')){
            print "Found skirun ${$skiruns_ref}{$way}{'name'}\n" if($debug > 2);
            print "Classed as ${$skiruns_ref}{$way}{'piste:difficulty'}\n" if($debug > 2);
            #Fill in any missing data that is required
            if(!defined(${$skiruns_ref}{$way}{'name'})){
                print "Skirun with way ID $way has no name. Setting to Unnamed_Run-$way\n" if($debug);
                ${$skiruns_ref}{$way}{'name'} = "Unnamed_Run-$way";
            }
            if(!defined(${$skiruns_ref}{$way}{'piste:difficulty'})){
                print "Skirun ${$skiruns_ref}{$way}{'name'} has no difficulty value. Setting to intermediate\n" if($debug);
                ${$skiruns_ref}{$way}{'piste:difficulty'} = "intermediate";
            }
            #Set the piste:difficulty to the style reference
            ${$skiruns_ref}{$way}{'style'} = '#' . ${$skiruns_ref}{$way}{'piste:difficulty'};
        }
        #Find all chairlifts (aerialways)
        elsif(exists(${$skiruns_ref}{$way}{'aerialway'})){
            print "Found chairlift ${$skiruns_ref}{$way}{'name'}\n" if($debug > 2);
            #Fill in any missing data that is required
            if(!defined(${$skiruns_ref}{$way}{'name'})){
                print "Chairlift with way ID $way has no name. Setting to Unnamed_Lift-$way\n" if($debug);
                ${$skiruns_ref}{$way}{'name'} = "Unnamed_Lift-$way";
            }
            #Set the style reference for chairlifts
            ${$skiruns_ref}{$way}{'style'} = '#Chairlift';
        }
        else{
            #If not a skirun/chairlift delete the key
            delete $skiruns_ref->{$way};
        }
    }
    return 1;
}
1;
