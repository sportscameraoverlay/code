#This module stores the config for SCPP
#All of these defaults can be overwritten (and are by user input)
#Config should be in here if it is common to more than one module,
#Or it can be set from command line options
#Or is likely to change
#
package SCPP::Config;

use strict;
use warnings;

BEGIN {
    require Exporter;
    our $VERSION = 1.01;
    our @ISA = qw(Exporter);
    our @EXPORT = qw();
    our @EXPORT_OK = qw($debug $print_err $save_subs @capture_res $ge_load_time $ge_first_point_wait $screen_stabilise_wait $screenshot_time $debug_lvl_for_screenshot $stabilize_video $shakiness $dir_look_ahead $dir_look_behind $dir_min_dist $smooth_direction $num_rolling_avg_pts $overlay_type $images_per_sec $base_image_transparency $ge_path_vid @overlay_pos @track_pos @track_frame_colour $track_frame_thickness $overlay_size $base_image_file @green @white @blue @black @red $font_normal $font_narrow $vid_out_framerate $vid_length_tol $input_vid_rotation $vid_out_codec $vid_out_quality $audio_out_codec $audio_out_bitrate $tmp_dir $subs_file_name $SCPP_dir setOverlayValues $map_file %kml_line_styles $kml_track_style $kml_flymode $kml_altitude $kml_tilt $kml_range $kml_altmode $kml_position_marker $kml_pos_marker_scale $xml_format $min_kml_path_dist $earths_radius);
    our %EXPORT_TAGS =(
	    debug => [qw($debug $print_err $save_subs)],
        gerecord => [qw(@capture_res $ge_load_time $ge_first_point_wait $screen_stabilise_wait $screenshot_time $debug_lvl_for_screenshot)],
	    imgstab => [qw($stabilize_video $shakiness)],
	    directionsmooth => [qw($dir_look_ahead $dir_look_behind $dir_min_dist $smooth_direction $num_rolling_avg_pts)],
        overlay => [qw($overlay_type $images_per_sec @overlay_pos $overlay_size @track_pos @track_frame_colour $track_frame_thickness)],
	    overlaysub => [qw($base_image_file @green @white @blue @black @red $font_normal $font_narrow)],
        video => [qw($vid_out_framerate $vid_length_tol $base_image_transparency $ge_path_vid @track_pos $input_vid_rotation)],
        vidoutset => [qw($vid_out_codec $vid_out_quality $audio_out_codec $audio_out_bitrate)],
        tmp => [qw($tmp_dir $subs_file_name $SCPP_dir)],
        kml => [qw($map_file $ge_first_point_wait $smooth_direction %kml_line_styles $kml_track_style $kml_flymode $kml_altitude $kml_tilt $kml_range $kml_altmode $kml_position_marker $kml_pos_marker_scale $xml_format $min_kml_path_dist $earths_radius)],
    );
}

#Common Settings
#################################################
#Debug
our $debug = 0; #Leave set low, can be set higher later
our $print_err = 1; #Whether or not to print errors to STDERR
our $save_subs = 1;

#Temp dirs
our $tmp_dir = "/tmp/contour_auth_$$/";
our $subs_file_name = "contour_auth_subs.log";

our $earths_radius = 6378000; #in metres
our $SCPP_dir;

#Video settings
#################################################
our $vid_out_framerate = 30;
our $vid_length_tol = 30; #Number of sec that the length of subs can differ from video length
#Video Output settings 
our $vid_out_codec = 'libx264';
our $vid_out_quality = 'hq';
our $audio_out_codec = 'aac';
our $audio_out_bitrate = '160k';
our $input_vid_rotation = 0; #No rotation unless specified

#Google earth path video file
our $ge_path_vid = "ge_record.mp4";

#Image stabilization
our $stabilize_video = 0; #0 = no image stabilization, 1 = stabilize image
our $shakiness = 6; #How shakey the video is - Min=1, Max=10

#Direction smoothing settings
#################################################
our $dir_look_ahead = 6;
our $dir_look_behind = 6;
our $dir_min_dist = 15; #in metres
our $smooth_direction = 1;
our $num_rolling_avg_pts = 3; #Set to 0 if no rolling average is needed

#Google Earth tour settings
#################################################
#Capture size
our @capture_res = (574, 514);

#Timing settings
our $ge_load_time=8;
our $ge_first_point_wait = 3;
our $screen_stabilise_wait = 0.8; #0.8sec
our $screenshot_time = 0.5; #Guesstimate of the time taken (sec) to take a screenshot (only used for progress display)

#Debug level that means regular screenshots are taken 
our $debug_lvl_for_screenshot = 2;

#KML generation settings
#################################################
our $map_file; #must be an OSM file
our %kml_line_styles = (
    #KML colour codes
    #In aabbggrr, 
    #aa=alpha (00 to ff); 
    #bb=blue (00 to ff); 
    #gg=green (00 to ff); 
    #rr=red (00 to ff)

    #These are the colours for the runs
    novice => {
        color => "ff00d300", #light green
        width => "4",
        'labelVisibility' => "1",
    },
    easy => {
        color => "ff1aad0f",#dark green
        width => "4",
        'labelVisibility' => "1",
    },
    intermediate => {
        color => "ff3818d2",#Red
        width => "4",
        'labelVisibility' => "1",
    },
    advanced => {
        color => "cc000000",#Black
        width => "4",
        'labelVisibility' => "1",
    },
    expert => {
        color => "ff2f0f42",#Dark Purple
        width => "4",
        'labelVisibility' => "1",
    },
    Chairlift => {
        color => "ff6f3b00",#Dark Blue
        width => "4",
        'labelVisibility' => "1",
    },
    Track => {
        color => "ff17e4ff",#Yellow
        width => "4",
        'labelVisibility' => "0",
    },
);
our $kml_track_style = '#Track';
our $kml_flymode = "smooth";
our $kml_altitude = "0";
our $kml_tilt = "45";
our $kml_range = "500";
our $kml_altmode = "relativeToGround";
our $kml_position_marker = "/home/paul/contour_auth/Images/pin-green.png";
$kml_position_marker = File::Spec->rel2abs($kml_position_marker) or die "Failed to convert $kml_position_marker to a absolute path";
our $kml_pos_marker_scale = "1";
our $xml_format = 2; #Sets how the xml is printed...
our $min_kml_path_dist = 10; #Min distance between points in paths imported from OSM before interpolation will occur

#Overlay settings
#################################################
our $overlay_type = 'speedo';

#Some colours (R,G,B)
our @green = (0,210,0);
our @black = (0,0,0);
our @red = (255,0,0);
our @blue = (0,0,255);
our @white = (255,255,255);

#Some Fonts
our $font_normal='/usr/share/fonts/truetype/ubuntu-font-family/Ubuntu-B.ttf';
our $font_narrow='/usr/share/fonts/truetype/ubuntu-font-family/Ubuntu-C.ttf';

#Track frame settings
our @track_frame_colour = @black;
our $track_frame_thickness = 4;

#Do not set these here, set below!
our $images_per_sec;
our $base_image_transparency;
our @overlay_pos;
our $overlay_size;
our $base_image_file;
our @track_pos; #If track pos is undef or 0 no GE track will be recorded
###############################################################################
#Subroutine that should be called to correctly set the values for the overlays
#This subroutine contains the common config between overlay types
#It needs to be called after the GPS period is know so it can check the settings
###############################################################################
sub setOverlayValues($){
    (my $GPS_period) = @_;

    #Overlay types
    if($overlay_type =~ /digital/) {
        $images_per_sec = 2; #This needs to be divisable wholey into the vid_out_framerate and GPS freq!
        $base_image_transparency = 80;
        @overlay_pos = (0, 100); #X,Y percentage position
        $overlay_size = 60;
        $base_image_file = 'Images/board-frosty.png';
        @track_pos = (1510, 710, 1918, 1078);
    }
    elsif($overlay_type =~ /speedo/) {
        $images_per_sec = 10;
        $base_image_transparency = 100;
        @overlay_pos = (0, 100); #X,Y percentage position
        $overlay_size = 70;
        $base_image_file = 'Images/speedo.png';
        @track_pos = (1550, 750, 1918, 1078);
    }

    else{
        #Die if the overlay does not match the above...
        die "$overlay_type is not a valid overlay type\n";
    }
 
    #Convert base image file to an absolute path
    $base_image_file = "$SCPP_dir/$base_image_file";

    #Check that the GPS period * images per sec is a whole num
    if(($images_per_sec * $GPS_period) !~ /^\d+\z/){
        die "The number of images per sec($images_per_sec) multiplied by the GPS period($GPS_period) is not a whole number.\n Please check the config module!\n";
    }
    #Check that the video framerate is divisable wholey by the GPS period
    if(($vid_out_framerate / $images_per_sec) !~ /^\d+\z/){
        die "The output video framerate($vid_out_framerate) is not divisable wholey by the number of images per sec($images_per_sec).\n Please check the config module!\n";
    }
    return 1;
}

1;
