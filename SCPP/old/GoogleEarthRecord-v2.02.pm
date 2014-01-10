#This module is used to record the output of a KML tour in Google Earth
#
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 25/04/13 First version as perl module
# 1.01  PJ 28/04/13 Module name change and changed variable/sig scoping
# 1.02  PJ 04/05/13 Added progress display and exception handling
# 1.03  PJ 04/05/13 Tried to fix exception handling
# 2.00  PJ 04/05/13 Now using threads
# 2.01  PJ 09/06/13 Fixed many bugs!
# 2.02  PJ 20/06/13 changed geometry to use arrays.
#
###############################################################################

package SCPP::GoogleEarthRecord; 
use strict;
use threads qw(stringify);
use threads::shared;
use warnings;
use GD;
use File::Copy;
use Time::HiRes qw(usleep time);
use Cwd 'abs_path';
use SCPP::Config qw(:debug :tmp :gerecord);
use SCPP::Common;

BEGIN {
    require Exporter;
    our $VERSION = 2.00;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(recordTourGE);
    our @EXPORT_OK = qw();
}

#Contatants that are local to this module and have to shouldn't change
my $display = 97; #Display # to use for the recording
my $capture_codec = 'libx264';
my $capture_quality = 'lossless_ultrafast';
my $log_file = "RecordGE.log";
my $ge_bin = '/usr/bin/google-earth';
my $xvfb_res = (1366, 768);
my @ge_sidebar_point = (30,120);
my @ge_sidebar_tour_point = (100,322);
my @ge_exit_point = (580,400);
my $ge_sidebar_colour = 13947080;
my $ge_conf_file = './SCPP/GoogleEarthPlus.conf';
my $ge_conf_file_loc = $ENV{"HOME"} . '/.config/Google/';
my $screenshot_count = 0; #Used to keep track of the screenshots taken (mostly for debug)
my $process_name = "Recording Track in Google Earth";
my $process_name_end = "Shutting down Google Earth and the Virtual Screen";
my $process_name_start = "Starting Virtual Screen and Google Earth";
my @capture_offset;

#Shared Vars
my $ge_status :shared = 0;
my $ge_cntrl :shared = 0;
my $xvfb_status :shared = 0;
my $xvfb_cntrl :shared = 0;
my $record_status :shared = 0;
my $record_cntrl :shared = 0;
my $control_status :shared = 0;
my $control_cntrl :shared = 1; #start straight away
my $control_thr; #Has to be defined out here so quitAll can use it
my %thread_map = (
    1 => 'Xvfb (Virtual Frame Buffer)',
    2 => 'Google Earth',
    3 => 'GE Record',
    4 => 'GE Control',
);

sub recordControl($$$);
sub run_xvfb();
sub run_ge($);
sub control_ge($$);
sub x11KeyPress($$$);
sub x11PointClick($$$$);
sub takeScreenshot($);
sub wait_sec($);

###############################################################################
#Main GE capture routine
#Requires the following:
#1)The path to the KML file to "Play"
#2)The output file to store the recording
#3)The time in seconds to record
#4)The framerate to record at
#5)A directory path to store all temp files
#6)The debug level
###############################################################################
sub recordTourGE($$$$){
    (my $kml_file, my $output_file, my $record_length, my $rec_framerate) = @_;

    sub quitAll($);
    $SIG{INT} = \&quitAll;
    $SIG{HUP} = \&quitAll;
    $SIG{TERM} = \&quitAll;

    #If debug level is above the specified level take screenshots
    my $take_screenshot = 0;
    my $num_screenshots = 1;
    if($debug >= $debug_lvl_for_screenshot){
        $take_screenshot = 1;
        $num_screenshots = 15;
    }

    #Calculate the total time the recording will take
    my $record_time = $record_length;
    #Change the time and size of recording if debug is high enough
    if($debug > 2){
        $record_time = $ge_load_time + $ge_first_point_wait + $record_length + (($screen_stabilise_wait * 5)/1000000) + ($screenshot_time * $num_screenshots);
        @capture_res = @xvfb_res; 
        @capture_offset = (0,0);
    }

    #Get the absolute path to the KML file as GE cannot work with relative paths
    $kml_file = abs_path($kml_file);
    print "KML File: $kml_file\n" if($debug > 1);

    my $xvfb_thr = threads->create(\&run_xvfb);
    my $ge_thr = threads->create(\&run_ge, $kml_file);
    my $record_thr = threads->create(\&recordControl, $output_file, $record_time, $rec_framerate);
    $control_thr = threads->create(\&control_ge, $take_screenshot, $record_length);
    my $exit_now = 0;
    my $exit_err = 0;
    while(!$exit_now){
        if(($xvfb_status > 0) and !$xvfb_thr->is_running()){
            $exit_now = 1;
            if($xvfb_status == 1){
                print "xvfb thread ended abnormally\n";
                $exit_err = 1;
            }
        }
        if(($ge_status > 0) and !$ge_thr->is_running()){
            if($ge_status == 1){
                $exit_now = 1; #Since this will exit early we only want to exit everything else on errors.
                print "GE thread ended abnormally\n";
                $exit_err = 1;
            }
        }
        if(($record_status > 0) and !$record_thr->is_running()){
            if($record_status == 1){
                print "Record thread ended abnormally\n";
                $exit_now = 1; #Since this will exit early we only want to exit everything else on errors.
                $exit_err = 1;
            }
        }
        if(($control_status > 0) and !$control_thr->is_running()){
            $exit_now = 1;
            if($control_status == 1){
                print "Control thread ended abnormally\n";
                $exit_err = 1;
            }
        }
    }
    #We must be done (or something ended abnormally)
    quitAll(0) if(!$exit_err);
    quitAll("D") if($exit_err);
    
    return 1;

}    
############################################# 
#Subroutine that is called to close all programs used in this module.
#Requires a 0 if called normally (not by sig handler)
#############################################
sub quitAll($){
    (my $sig_name) = @_;

    #Tell all threads to exit if waiting for control
    $xvfb_cntrl = $record_cntrl = $ge_cntrl = 2;
    $control_thr->kill('STOP') if($control_thr->is_running());

    #Print How we died
    if($sig_name eq "D"){
        print "Abnormal Exit! Killing all background tasks\n";
    }elsif($sig_name){
        print "\nCaught SIG$sig_name, Killing all background tasks\n";
    }else{
        print "Finished Recording, Exiting now...\n" if($debug);
    }

    #Wait for threads to stop
    usleep(500 * 1000); #500ms
    progress($process_name_end, 60) if(!$sig_name);

    #Kill any remaining processes
    my @ge_pids;
    my @xvfb_pids;
    my @record_pids;

    my @ps_lines = readpipe('ps -ef');
    foreach my $line (@ps_lines){
        chomp $line;
        if($line =~ /^\w+\s+(\d+)\s.+Xvfb :$display -screen 0 $xvfb_res[0]x$xvfb_res[1]/){
            print "Xvfb PID to Kill: $1\n" if($debug > 2);
            unshift @xvfb_pids, $1;
        }
        if($line =~ /^\w+\s+(\d+)\s.+google-earth/){
            print "GE PID to Kill: $1\n" if($debug > 2);
            unshift @ge_pids, $1;
        }
        if($line =~ /^\w+\s+(\d+)\s.+ffmpeg/){
            print "Record PID to Kill: $1\n" if($debug > 2);
            unshift @record_pids, $1;
        }
    }

    #Kill all the external programs
    print "GE pids to kill: @ge_pids\n" if(@ge_pids);
    kill(15, @ge_pids);

    print "Record pids to kill: @record_pids\n" if(@record_pids);
    kill(15, @record_pids);

    print "Xvfb pids to kill: @xvfb_pids\n" if($debug and @xvfb_pids);
    kill(15, @xvfb_pids);

    #wait for threads to exit cleanly
    usleep(100 * 1000); #100ms
    progress($process_name_end, 80) if(!$sig_name);

    #Join all threads and try to get the exit codes 
    my @joinable_threads = threads->list(threads::joinable);
    foreach my $thread (@joinable_threads){
        my $thread_exit_status = $thread->join();
        $thread_exit_status = 'undef' if(!defined($thread_exit_status));
        print "Thread $thread_map{$thread} exited with status: $thread_exit_status\n" if($debug > 1);
    }

    die "RecordGE module exiting now...\n" if($sig_name);
    progress($process_name_end, 100) if(!$sig_name);
    return 1;
}

################################################################################
#Virtual Frame buffer thread
################################################################################
sub run_xvfb(){
    $xvfb_status = 1;
    print "Running xvfb thread\n" if($debug > 1);
    while($xvfb_cntrl == 0){
        usleep(50 * 1000)#50ms
    }
    if($xvfb_cntrl == 1){ #if set to anything else exit...
        print "Starting Virtual Display\n" if($debug);
        my @xvfb_cmd = ('startx', '--', '/usr/bin/Xvfb', ":$display", '-screen', '0', "$xvfb_res[0]x$xvfb_res[1]x24");
        system("./SCPP/run_command.pl $debug \'$tmp_dir/$log_file\' @xvfb_cmd");
        print "Finished XVFB cmd, Exited with $?\n" if($debug > 1);
    }
    $xvfb_status = 2;
    return $?;
}

################################################################################
#Google Earth thread
################################################################################
sub run_ge($){
    (my $kml_file) = @_;
    $ge_status = 1;
    print "Running Google Earth thread\n" if($debug > 1);
    while($ge_cntrl == 0){
        usleep(50 * 1000)#50ms
    }
    if($ge_cntrl == 1){ #if set to anything else exit...
        print "Starting Google Earth\n" if($debug);
        
        #Lets copy over a good config if we have one
        if(-e $ge_conf_file){
            print "Coping over the GE conf file: $ge_conf_file to $ge_conf_file_loc\n" if($debug > 1);
            `mkdir -p $ge_conf_file_loc`;
            copy($ge_conf_file, $ge_conf_file_loc) or die $!;
        }            
        system("./SCPP/run_command.pl $debug \'$tmp_dir/$log_file\' DISPLAY=:$display $ge_bin $kml_file");
        print "Google Earth finished, Exited with: $?\n" if($debug > 1);
    }
    $ge_status = 2;
    return $?;
}

################################################################################
#Desktop Record thread
#Requires the following to be passed in:
#1) Output file to record to
#2) Length in seconds to record for
#3) Framerate to capture at
################################################################################
sub recordControl($$$){
    (my $out_file, my $length, my $framerate) = @_;
    print "Running Desktop Record thread\n" if($debug > 1);
    $record_status = 1;
    
    #Calculate the capture res and offset
    $capture_res[0] = $xvfb_res[0] if($capture_res[0] > $xvfb_res[0]); 
    $capture_res[1] = $xvfb_res[1] if($capture_res[1] > $xvfb_res[1]); 
    $capture_offset[0] = ($xvfb_res[0] - $capture_res[0]) / 2;
    $capture_offset[1] = ($xvfb_res[1] - $capture_res[1]) / 3; #Divide by 3 so to "look forward"

    #Record Command
    my $ffmpeg_inp_var = ':' . $display . '.0+' . $capture_offset[0] . ',' . $capture_offset[1];
    my @record_cmd = ('/usr/bin/ffmpeg', '-y', '-t', "$length", '-f', 'x11grab', '-s', "$capture_res[0]x$capture_res[1]", '-r', "$framerate", '-i', "$ffmpeg_inp_var", '-vcodec', "$capture_codec", '-vpre', "$capture_quality",  "$out_file",);
    
    while($record_cntrl == 0){
        usleep(50 * 1000)#50ms
    }
    if($record_cntrl == 1){ #if set to anything else exit...
        print "Starting Recording\n" if($debug);
        system("./SCPP/run_command.pl $debug \'$tmp_dir/$log_file\' @record_cmd");
        print "Finished Recording, Exited with $?\n" if($debug > 1); 
    }
    $record_status = 2;
    return $?;
}

################################################################################
#GE record control thread
################################################################################
sub control_ge($$){
    (my $take_screenshot, my $record_length) = @_;

    #Setup sig handler to exit if required
    $SIG{'STOP'} = sub {
        print "Killing GE Record cntrl\n" if($debug > 1);
        threads->exit();
    };

    print "Running GE Control thread\n" if($debug > 1);
    $control_status = 1;

    progress($process_name_start, 0);
    #Start the XVFB
    $xvfb_cntrl = 1;
    wait_sec(1);
    takeScreenshot("X_started_on_$display") if($take_screenshot);
    progress($process_name_start, 5);

    #Start the recording early if debug is set...
    $record_cntrl = 1 if($debug > 2);
    
    #Start GE
    $ge_cntrl = 1;
    progress($process_name_start, 10);

    #Wait for GE to load/stabilise
    print "Waiting for Google Earth to load\n" if($debug);
    wait_sec($ge_load_time);
    takeScreenshot("GE_started_after_$ge_load_time") if($take_screenshot);
    progress($process_name_start, 75);

    #Control GE via xdotool
    ##################################

    #Get GE's window ID
    my @window_id = readpipe("DISPLAY=:$display xdotool search --onlyvisible --name 'Google Earth'");
    chomp @window_id;
    print "GE Window ID: @window_id\n" if($debug > 1);
    die "Discovered more than one GE window!! @window_id\n" if(scalar(@window_id) > 1);
    die "Could not find the GE window!!\n" if(scalar(@window_id) == 0);
    takeScreenshot("Got_GE_windowID") if($take_screenshot);
    
    #Determine if GE is already fullscreen or not
    my @window_geo = readpipe("DISPLAY=:$display xdotool getwindowgeometry $window_id[0]");
    chomp @window_geo;
    print "GE Window Geometry: @window_geo\n" if($debug > 1);
    if($window_geo[2] =~ /Geometry: $xvfb_res[0]x$xvfb_res[1]/){
        print "GE Already Fullscreen\n" if($debug > 1);
    }else{
        x11KeyPress($display,$window_id[0],'F11');
    }
    wait_sec($screen_stabilise_wait); #wait for screen to stabilise
    takeScreenshot("GE_fullscreen") if($take_screenshot);
    
    #Determine if the sidebar is already up
    #To do this take a screenshot and check a known position on the sidebar for the correct colour.
    my $ge_screenshot_file = takeScreenshot("GE-sidebar");
    die "Failed to determine if GE has the sidebar open" if(!$ge_screenshot_file);
    my $screenshot = GD::Image->newFromPng($ge_screenshot_file, 1);
    my $index = $screenshot->getPixel(@ge_sidebar_point);
    print "GE Sidebar Colour Index: $index\n" if($debug > 1);
    if($index == $ge_sidebar_colour){
        print "GE Sidebar already open\n" if($debug > 1);
    }else{
        x11KeyPress($display,$window_id[0],'alt+ctrl+b');
    }
    wait_sec($screen_stabilise_wait); #wait for screen to stabilise
    takeScreenshot("GE_sidebar_open") if($take_screenshot);
    progress($process_name_start, 80);
    
    #Play Tour
    #Note: For this to work the gx:Tour element must be first in the KML file
    x11PointClick($display,$window_id[0],$ge_sidebar_tour_point[0],$ge_sidebar_tour_point[1]);
    #x11KeyPress($display,$window_id[0],'Down');
    x11KeyPress($display,$window_id[0],'Return');
    print "GE tour started\n" if($debug);
    takeScreenshot("GE_tour_started") if($take_screenshot);
  
    #Now remove the sidebar
    x11KeyPress($display,$window_id[0],'alt+ctrl+b');
    wait_sec($screen_stabilise_wait); #wait for screen to stabilise
    takeScreenshot("GE_sidebar_closed") if($take_screenshot);
    
    #Wait for the time to the first point kml point and then start recording (remove the time for screensots, waiting and xdotool)
    wait_sec($ge_first_point_wait - $screen_stabilise_wait - ($take_screenshot * $screenshot_time * 3));
    takeScreenshot("GE_recording_starting") if($take_screenshot);
    progress($process_name_start, 100);
    
    #Start the recording (normally)
    $record_cntrl = 1 if($debug <= 2);

    takeScreenshot("GE_recording_started") if($take_screenshot);
    
    progress($process_name, 0);
    my $start_time = time;
    #Wait for the tour to finish
    while($record_status == 1){
        usleep(50 * 1000); #50ms
        my $elapsed_time = time - $start_time;
        my $percent_done = ($elapsed_time / $record_length) * 100;
        progress($process_name, $percent_done) if($percent_done < 100);
    }
    takeScreenshot("GE_tour_finished") if($take_screenshot);
    progress($process_name, 100);
    
    #Try to exit GE nicely
    progress($process_name_end, 0);
    x11KeyPress($display,$window_id[0],'alt+f');
    x11KeyPress($display,$window_id[0],'Up');
    x11KeyPress($display,$window_id[0],'Return');
    takeScreenshot("GE_exit_box_open") if($take_screenshot);
    wait_sec($screen_stabilise_wait); #Wait for exit box to appear
    progress($process_name_end, 20);
    takeScreenshot("GE_exit_box_open_stabilised") if($take_screenshot);
    x11PointClick($display,$window_id[0],$ge_exit_point[0],$ge_exit_point[1]);
    takeScreenshot("GE_clicked_exit_box") if($take_screenshot);
    wait_sec($screen_stabilise_wait); #Wait for GE to exit
    takeScreenshot("GE_closed") if($take_screenshot);         
    progress($process_name_end, 40);

    $control_status = 2;
    return 1;
}

###############################################################################
#Subroutine to issue X11 keyboard commands using xdotool
#Requires the following:
#1) Display #
#2) Window #
#3) key to be pressed
###############################################################################
sub x11KeyPress($$$){
    (my $disp, my $window, my $key) = @_;
    my $command = "DISPLAY=:$disp xdotool key --window $window $key";
    warn "$command\n" if($debug > 1);
    if(system("$command") != 0) {
        die "X11 keypress failed: $?, Command: $command";
    }else{
        return 1;
    }
}
###############################################################################
#Subroutine to click a point using the xdotool
#Requires the following:
#1) Display #
#2) Window #
#3) X cords of point to be clicked
#4) Y cords of point to be clicked
###############################################################################
sub x11PointClick($$$$){
    (my $disp, my $window, my $x_point, my $y_point) = @_; 
    my $command = "DISPLAY=:$disp xdotool mousemove --sync $x_point $y_point click 1";
    warn "$command\n" if($debug > 1);
    if(system("$command") != 0) {
        die "X11 click failed: $?, Command: $command";
    }else{
        return 1;
    }
}

###############################################################################
# Subroutine to take a screenshot of whats going on and save to the tmp folder
# Requires a descriptive name of the screenshot
###############################################################################
sub takeScreenshot($){
    (my $ss_name) = @_;
    $screenshot_count++;
    my $ss_file = $tmp_dir . '/' . $screenshot_count . '-' . $ss_name . '.png';
    my $command = 'DISPLAY=:' . $display . ' import -window root ' . $ss_file;
    warn "$command\n" if($debug > 2);
    if(system("$command") != 0) {
        die "Screenshot failed: $?, Command: $command";
    }else{
        return $ss_file;
    }
}

#################################################
#Subroutine to wait for a specific number of seconds
#Used to get around the issue where sending a signal to a thread does not interupt the sleep
#################################################
sub wait_sec($){
    (my $wait_time) = @_;
    print "Sleeping for $wait_time sec\n" if($debug > 2);
    my $end_time = time + $wait_time;
    while(time < $end_time){
        usleep(10 * 1000); #10msec
    }
    print "Done sleeping for $wait_time sec\n" if($debug > 2);
    return 1;
}
1;
