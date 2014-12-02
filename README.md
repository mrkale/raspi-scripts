Scripts for Raspberry Pi
=====
This project contains a set of bash scripts,
which are useful for backing up, controlling and maintaining 
the operating system. They usually do not relate
to each other and should be considered as standalone ones.
On the other hand, they all serve for better operating
Raspberry Pi computer.

Each of scripts has got its own description (.md) file
with details about its usage and purpose.

scripts_lib.sh
=====
The script is supposed to be a library for all remaining working scripts.
It should be located in the same folder as respective script either directly
or as a symbolic link.

imagesd.sh
=====
The script is supposed to be used either for manual, interactive backup
of the SD card to an image file or for automatic backup under cron with help
of ***dd*** utility. It displays a progress bar of creating the image file,
if it is not suppressed.
The image file can be mount to Raspberry Pi directly as a separate device
or used for restoring and cloning an SD card.

backupsd.sh
=====
The script is supposed to be used for backing up root file system 
to a backup folder with help of ***rsync*** utility. It may be used manually
or under cron. It is a fast alternative to backing up the entire image of SD card. 

syncfiletimestamp.sh
=====
The script sets the modification date and time of input files according to the
timestamp included in their names, i.e., it synchronizes the files' timestamp
with their names. It is useful for backup image files after copying them from
some location to a target location without preserving modification time. It
allows to continue in rotating backup files based on their modification time.

check_temp.sh
=====
The script checks the internal temperature of the SoC.
If the temperature exceeds a warning limit as a percentage of
maximal limit written in the system, it outputs an alert message.
If the temperature exceeds a shutdown limit as a percentage of
maximal limit, it outputs a fatal message and shuts down the system.

check_conn.sh
=====
The script checks if a network connection to the router as well as
to the internet is active and working. It sends the status of connection
to Google Analytics and logs it into the system log as well. It can restart
particular wlan interface after declared number of connection failures as well
as reboot the system.

check_dbs.sh
=====
The script is supposed to check database tables of type *MyISAM*, *InnoDB*, and *Archive*
in MySQL databases. By default the script outputs just the error messages about
corrupted tables, so that it is suitable for periodic checking under cron.

iot_thingspeak.sh
=====
The script reads system temperature and temperatures from connected DS18B20 sensors
and sends data to webservice ThingSpeak.com. At the same time the scripts stores
that data to a Round Robin Database. If it does not exit yet, the script creates one.

rrd_graph_temp.sh
=====
The script reads Round Robin Database with temperatures and creates pictures with
graphs and locate them to a web server document folder for visualizing them.

