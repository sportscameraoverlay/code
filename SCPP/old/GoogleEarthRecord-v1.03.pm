#This module is used to record the output of a KML tour in Google Earth
#
#Requires libtry-tiny-perl package in ubuntu
#Paul Johnston
###############################################################################
# History
###############################################################################
# 1.00  PJ 25/04/13 First version as perl module
# 1.01  PJ 28/04/13 Module name change and changed variable/sig scoping
# 1.02  PJ 04/05/13 Added progress display and exception handling
#
###############################################################################

package SCPP::GoogleEarthRecord; 
use strict;
use warnings;
use GD;
use Time::HiRes qw(usleep time);
use Cwd 'abs_path';
use SCPP::Config qw(:debug :tmp :gerecord);
use SCPP::Common;
use POSIX ":sys_wait_h";

BEGIN {
    require Exporter;
    our $VERSION = 1.02;
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
my $xvfb_res = '1366x768';
my @ge_sidebar_point = (30,120);
my @ge_sidebar_tour_point = (100,300);
my @ge_exit_point = (580,400);
my $ge_sidebar_colour = 13947080;

my $screenshot_count = 0; #Used to keep track of the screenshots taken (mostly for debug)
my $parent_pid; #Used when killing
my $process_name = "Recording Track in Google Earth";
my %watched_pids;

sub x11KeyPress($$$);
sub x11PointClick($$$$);
sub recordControl($$$);
sub recordGEProgress($);
sub takeScreenshot($);
sub quitAll($);

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

    $parent_pid = $$;
    print "RecordGE Parent PID: $parent_pid\n" if($debug > 1);

    #Catch the folowing signals so we can kill all background tasks
    $SIG{INT} = \&quitAll;
    $SIG{HUP} = \&quitAll;
    $SIG{TERM} = \&quitAll;

    #Fork and run the main routine storing the pid in %watched_pids
    $watched_pids{'main_pid'} = fork;
    defined $watched_pids{'main_pid'} or die "Main GE record subroutine fork failed: $!";
    #Child Process
    ########################################################################################
    if ($watched_pids{'main_pid'} == 0) {
        
        #If debug level is above the specified level take screenshots
        my $take_screenshot = 0;
        my $num_screenshots = 1;
        if($debug >= $debug_lvl_for_screenshot){
            $take_screenshot = 1;
            $num_screenshots = 15;
        }

        #Calculate the total time the recording will take
        my $total_time = $record_length + $ge_load_time + $ge_first_point_wait + (($screen_stabilise_wait * 5)/1000000) + 1 + ($screenshot_time * $num_screenshots);
        #And fork off a process to update this
        recordGEProgress($total_time);

        #Get the absolute path to the KML file as GE cannot work with relative paths
        $kml_file = abs_path($kml_file);
        print "KML File: $kml_file\n" if($debug > 1);

        print "Starting Virtual Display\n" if($debug);
        #Start the virtual display
        $watched_pids{'xvfb_pid'} = fork;
        defined $watched_pids{'xvfb_pid'} or die "Xvfb fork failed: $!";
        if ($watched_pids{'xvfb_pid'} == 0) {# child
            my $xvfb_res1 = $xvfb_res . 'x24';
            my @xvfb_cmd = ('startx', '--', '/usr/bin/Xvfb', ":$display", '-screen', '0', "$xvfb_res1", );
            print "@xvfb_cmd\n" if($debug > 1);
            open STDOUT, '>', "$tmp_dir/$log_file" if($debug <= 3); #Turn off the Xvfb logging if debug is off
            open STDERR, '>', "$tmp_dir/$log_file" if($debug <= 3); #Turn off the Xvfb logging if debug is off
            #exec {$xvfb_cmd[0]} @xvfb_cmd;
            system(@xvfb_cmd) == 0 or die "Running Virtual Display failed with exitcode: $?";
            delete $watched_pids{'xvfb_pid'};
            exit;
        }
        print "Virtual screen PID: $watched_pids{'xvfb_pid'}\n" if($debug > 1);
        sleep 1;
        takeScreenshot("X_started_on_$display") if($take_screenshot);
    
        #Start the recording early if debug is set...
        if($debug > 2){
            recordControl($output_file, $total_time - 1, $rec_framerate);
        }
    
        #Start GE
        $watched_pids{'ge_pid'} = fork;
        defined $watched_pids{'ge_pid'} or die "GE fork failed: $!";
        if ($watched_pids{'ge_pid'} == 0) {# child
            my $ge_cmd = 'DISPLAY=:' . $display . ' ' . $ge_bin . ' ' . $kml_file;
            print "$ge_cmd\n" if($debug > 1);
            open STDOUT, '>', "$tmp_dir/$log_file" if($debug <= 3); #Turn off the GE logging if debug is off
            open STDERR, '>', "$tmp_dir/$log_file" if($debug <= 3); #Turn off the GE logging if debug is off
            system($ge_cmd) == 0 or die "Running GoogleEarth failed with exitcode: $?";
            delete $watched_pids{'ge_pid'};
            exit;
        }
        print "Google Earth PID: $watched_pids{'ge_pid'}\n" if($debug > 1);
    
        #Wait for GE to load/stabilise
        print "Waiting for Google Earth to load\n" if($debug);
        sleep $ge_load_time;
        takeScreenshot("GE_started_after_$ge_load_time") if($take_screenshot);
    
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
        if($window_geo[2] =~ /Geometry: $xvfb_res/){
            print "GE Already Fullscreen\n" if($debug > 1);
        }else{
            x11KeyPress($display,$window_id[0],'F11');
        }
        usleep($screen_stabilise_wait); #wait for screen to stabilise
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
        usleep($screen_stabilise_wait); #wait for screen to stabilise
        takeScreenshot("GE_sidebar_open") if($take_screenshot);
    
        #Play Tour
        #Note: For this to work the gx:Tour element must be first in the KML file
        x11PointClick($display,$window_id[0],$ge_sidebar_tour_point[0],$ge_sidebar_tour_point[1]);
        #x11KeyPress($display,$window_id[0],'Down');
        x11KeyPress($display,$window_id[0],'Return');
        takeScreenshot("GE_tour_started") if($take_screenshot);
    
        #Now remove the sidebar
        x11KeyPress($display,$window_id[0],'alt+ctrl+b');
        usleep($screen_stabilise_wait); #wait for screen to stabilise
        takeScreenshot("GE_sidebar_closed") if($take_screenshot);
    
        #Wait for the time to the first point kml point and then start recording (remove the time for screensots, waiting and xdotool)
        usleep (($ge_first_point_wait * 1000000) - $screen_stabilise_wait - ($take_screenshot * $screenshot_time * 3) - 50000);
        takeScreenshot("GE_recording_starting") if($take_screenshot);
    
        #Start the recording (normally)
        recordControl($output_file, $record_length, $rec_framerate) if($debug <= 2);
        takeScreenshot("GE_recording_started") if($take_screenshot);
    
        #Wait for the tour to finish
        sleep $record_length;
        takeScreenshot("GE_tour_finished") if($take_screenshot);
    
        #Try to exit GE nicely
        x11KeyPress($display,$window_id[0],'alt+f');
        x11KeyPress($display,$window_id[0],'Up');
        x11KeyPress($display,$window_id[0],'Return');
        takeScreenshot("GE_exit_box_open") if($take_screenshot);
        usleep($screen_stabilise_wait); #Wait for exit box to appear
        takeScreenshot("GE_exit_box_open_stabilised") if($take_screenshot);
        x11PointClick($display,$window_id[0],$ge_exit_point[0],$ge_exit_point[1]);
        takeScreenshot("GE_clicked_exit_box") if($take_screenshot);
        usleep($screen_stabilise_wait); #Wait for GE to exit
        takeScreenshot("GE_closed") if($take_screenshot);         

        #Remove the pid from being monitored, This should cause the watcher to quit.
        delete $watched_pids{'main_pid'};
        exit;
    }

    print "RecordGE Main Child PID: $watched_pids{'main_pid'}\n" if($debug > 1);

    #Parent (watch the children and kill them all if one dies)
    my $dead_child = 0;
    while(!$dead_child and defined($watched_pids{'main_pid'})){
        foreach my $child (keys %watched_pids){
            print "Checking child $child with PID $watched_pids{$child}\n" if($debug > 2);
            my $pid_running = kill 0, $watched_pids{$child};
            if($pid_running){
                print "Child $child is Running\n" if($debug > 2);
            }else{
                $dead_child = 1;
                quitAll("D");
            }
        } 
        usleep(1000 * 500); #0.5sec  
    }

    quitAll(0);
    progress($process_name, 100);
    return 1;
}

###############################################################################
#Subroutine that is called to close all programs used in this module.
#Requires a 0 if called normally (not by sig handler)
###############################################################################
sub quitAll($){
    (my $sig_name) = @_;

    #If we are a child exit now
    if(($$ != $parent_pid)){
        print "Child PID $$ exiting now\n" if($debug > 1);
        exit;
    }

    #Print How we died
    if($sig_name eq "D"){
        print "Abnormal Exit. Called from parent block\n" if($debug > 1);
    }elsif($sig_name){
        print "\nCaught SIG$sig_name, Killing all background tasks...\n";
    }else{
        print "Finished Recording, Exiting now...\n" if($debug);
    }

    #Make sure all of the child PIDs are dead
    foreach my $child (keys %watched_pids){
        print "Killing $child with PID: $watched_pids{$child} Now\n" if($debug > 1);
        kill(15, $watched_pids{$child});
    }
 
    #Kill any remaining processes
    my @ge_pids;
    my @xvfb_pids;
    my @record_pids;

    my @ps_lines = readpipe('ps -ef');
    foreach my $line (@ps_lines){
        chomp $line;
        if($line =~ /^\w+\s+(\d+)\s.+Xvfb :$display -screen 0 $xvfb_res/){
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

    die "RecordGE module exiting now...\n" if($sig_name);
    return 1;
}
###############################################################################
#Subroutine to control the desktop recording
#Requires the following to be passed in:
#1) Output file to record to
#2) Length in seconds to record for
#3) Framerate to capture at
###############################################################################
sub recordControl($$$){
    (my $out_file, my $length, my $framerate) = @_;

    #Record Command
    my $ffmpeg_inp_var = ':' . $display . '.0+' . $capture_offset[0] . ',' . $capture_offset[1];
    my @record_cmd = ('/usr/bin/ffmpeg', '-y', '-t', "$length", '-f', 'x11grab', '-s', "$capture_res", '-r', "$framerate", '-i', "$ffmpeg_inp_var", '-vcodec', "$capture_codec", '-vpre', "$capture_quality",  "$out_file",);
    push @record_cmd, "2>$tmp_dir/$log_file" if($debug <= 3); #Turn off the record commands logging if debug is off

    #Fork the record command 
    $watched_pids{'record_pid'} = fork;
    defined $watched_pids{'record_pid'} or die "Record fork failed: $!";
    if ($watched_pids{'record_pid'} == 0) { # child
        print "Starting Recording\n" if($debug);
        print "Record Cmd: @record_cmd\n" if($debug > 1);
        `@record_cmd`;
        #Should die if fails....
        delete $watched_pids{'record_pid'};
        exit;
    }
    print "Record PID: $watched_pids{'record_pid'}\n" if($debug > 1);
    return 1;
}

###############################################################################
#Subroutine that is forked to display progress
#Requires the total time that the record process will take
###############################################################################
sub recordGEProgress($){
    (my $total_time) = @_;

    $watched_pids{'progress_pid'} = fork;
    defined $watched_pids{'progress_pid'} or die "Progress fork failed: $!";
    if ($watched_pids{'progress_pid'} == 0) { # child
        progress($process_name, 0);
        print "$process_name...\n" if($debug);
        print "Recording GE tour will take $total_time sec\n" if($debug);
        my $end_time = time + $total_time;
        print "End Time: $end_time, Current Time " . time . "\n" if($debug > 1);
        while($end_time > time){
            my $percent_done = (($total_time - ($end_time - time)) / $total_time) * 100;
            progress($process_name, $percent_done);
            usleep(1000 * 100); #100ms
        }
        print "Finished according to recordGEProgress\n" if($debug);
        delete $watched_pids{'progress_pid'};
        exit;
    }

    print "Progress update PID: $watched_pids{'progress_pid'}\n" if($debug > 1);
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
1;
