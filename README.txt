SportsCameraOverlay is a command line facility to overlay GPS info on videos taken with a sports (helmet) camera.

Currently tested and working with a Contour GPS and a Contour+2 camera.
The GPS enabled line of contour cameras store the GPS (NMEA sentences) in the subtitles of the video file, so using this program with a GPS enabled contour camera simplifies things as there is no need to line up the starting points of the video and the GPS data.

The default behaviour of this program is to create both a video file with the "Speedo" overaly and a kml file that can be played back in Google Earth or similar.

This program can also be passed a file that contains GPS info and overlay this on any video.
This way the program can be used for overlaying GPS info onto any brand of sports camera.

Currently two overlay types are available, a "speedo" overlay and a "digital" (textual) overlay designed around snowsports.

A few sample videos:
http://www.youtube.com/watch?v=RHWcOntLT5Q
http://www.youtube.com/watch?v=HelsKZeIRlM

INSTALLATION
##################################################
Currently this project will only run on linux (and possibly other unix OS's).

This program requires the following:
*Perl (Tested on 5.14.2 - I think any recent version of perl will work though, Let me know if not!)
*The perl GD library (Tested on 2.46 - Again let me know if a version doesn't work)
*The perl libxml library (Tested on 1.89 - Again let me know if a version doesn't work)

##Ubuntu/Debian based##
To install on a debian like OS run the following:

1)Install perl and required libraries
 sudo apt-get install perl libgd-gd2-perl libxml-libxml-perl
2)Download SportsCameraOverlay and untar
 tar -xvzf sportscameraoverlay.tar.gz

If you want the (highly unstable) google earth track recording you will also need to following packages:
*Xvfb
*xdotool
*google earth < 7 (I'm using 6.0.3)
*The ubuntu version of ffmpeg
eg:
 sudo apt-get install xvfb xdotool ffmpeg
 Then install the google earth binary:
 ./GoogleEarthLinux.bin
 
USAGE
##################################################
To use this program run the SportsCameraOverlay.pl executable from a terminal as follows:
 ./SportsCameraOverlay.pl [-k|K] [-tsv] [-o overlay_type] [-m map_file] [-r rotation] [-f external_gps_file] input_video_file
 ./SportsCameraOverlay.pl [-k|K] [-tsv] [-o overlay_type] [-m map_file] [-r rotation] -b input_video_folder

SportsCameraOverlay creates an overlayed video in the same directory as the original with the -overlay suffix appended to the filename.

Options
        -b input_video_folder
              Run SportsCameraOverlay in batch mode. This will overlay all files in the input_video_folder with the overlay specified. This mode is only available when the GPS data is stored in the video file.

        -f external_gps_file
              Use an external GPS file as the source of GPS info. When using this option make sure that the first NMEA sentence in the GPS file lines up with the start of the video. Also the GPS file must contain both $GPRMC and $GPGGA NMEA sentences in a periodic fashion.

        -k    
              Only create a kml "tour" file from the input video. This can be played back with programs like Google Earth.

        -K    
              Do not create a kml tour file.

        -m map_file
              Add data in an OSM (open street map) formatted file to the kml output. If not only creating the kml output (-k option) then this option also adds the data to the track overlay (-t option). Currently only skirun and skilift data is placed into the kml file.

        -o overlay_type
              Specify the overlay type. The current overlays are "speedo" and "digital". The default is speedo.

        -r rotation
              Rotate the input video by rotation degrees. Useful if a video was filmed upside down etc.

        -s
              Stabilize the output video. This setting is not currently implemented!

        -t
              Add the track overlay to the video. This is currently created by running Google Earth in a virtual X screen, playing a kml tour in GE and recording its output using ffmpeg to capture the screen. Since there is no easy way to control what GE does (ie start the kml tour playing) the xdotool is used to control GE. The biggest drawback with this method of capturing the track overlay is that GE is very prone to crashing - especially when loading a large kml file.
              If you really want to use this option you will have to install Xvfb, Google Earth and the xdotool. It is also highly probable that you will have to alter some of the settings in the Config file for SportsCameraOverlay.

        -v
              Be verbose. Passing multiple -v prints out more debug. Currently using up to -vvvvvv.

EXAMPLES
#################################################
To overlay FILE0001.MOV that has the GPS info contained in the subtitles (video taken with a contour camera), with the default "speedo" overlay:
 ./SportsCameraOverlay.pl FILE0001.MOV

To overlay NOGPS02.MOV that does not contain any GPS data in the subtitles, with GPS data from GPSDATA.txt:
 ./SportsCameraOverlay.pl -f GPSDATA.txt NOGPS02.MOV

To overlay all files in directory /home/bob/contour_videos with the digital overlay:
 ./SportsCameraOverlay.pl -b /home/bob/contour_videos -o digital

COPYRIGHT
#################################################
Copyright  ©  2013 - 2014  Paul Johnston.  

License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

SUPPORT
#################################################
If you do find this useful send me an email!
malooute at gmail

Also let me know of any ideas for future improvements/overlays, or feel free to submit me a patch!

RELEASE NOTES
#################################################
2.8    Bug fixes mostly.
       Fixed GPS period bug
       Now downloading ffmpeg if it doesn't exist in the cwd
       Also changed some options/defaults regarding kml generation

2.7    Removed the requirement for melt
       Now using ffmpeg from the cwd if it is present

2.6    Added option to use an external GPS file (-f option)
       Modified timestamp code to allow for greater accuracy
       Also fixed a few bugs

2.5    First upload to Sourceforge
       Added option to batch process a directory full of files
