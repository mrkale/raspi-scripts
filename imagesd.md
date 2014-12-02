Backup SD card to image file
=====
The script is supposed to be used either for manual, interactive backup
of the SD card to an image file or for automatic backup under cron with help
of ***dd*** utility. It displays a progress bar of creating the image file,
if it is not suppressed.

Name
=====
**imagesd.sh** - backup entire SD card to an image file

Synopsis
=====
    imagesd.sh [OPTION [ARG]] [backup_folder]

Description
=====
Script makes a binary backup of the entire SD card to a backup location as an image file
and displays progress of the backing up process if it is not suppressed.

- Script has to be run under root privileges (sudo ...).
- In manual mode the progress bar is displayed.
- From cron the script should be user in quiet mode.
- Image file name is composed of current hostname and current datetime.
- Image file is not compressed and can be mount as an external source directly.
- Script stops declared services during the backup process.
- All essential parameters are defined in the section of configuration parameters.
  Their description is provided locally. Script can be configured by changing values
  of them.
- Configuration parameters in the script can be overriden by the corresponding ones
  in a configuration file declared in the command line.
- Script performes rotating backup, i.e., it deletes obsolete backup files older than
  predefined number of days (default 15) before the current time of the backup process.
- In simulation mode the script uses 'touch' instead of 'dd', so that it creates
  an empty backup image file as well as it does not executes rotation backup files.

Example of backup image file (the placeholder *<hostname\>* is replaced
with real box hostname):

    <hostname>_2013-12-31_23h59m.img

Options and arguments
=====
    -h                 help: show this help and exit
    -s                 simulate: perform dry run without writing to backup folder and rotating logs
    -V                 Version: show version information and exit
    -c                 configs: print listing of all configuration parameters
    -l log_level       logging: level of logging intensity to syslog
                       0=none, 1=errors (default), 2=warnings, 3=info, 4=full
    -o verbose_level   output: level of verbosity
                       0=none, 1=errors (default), 2=mails, 3=info, 4=functions, 5=full
    -m                 mail: display processing messages suitable for emailing from cron; alias for '-o2'
    -v                 verbose: display all processing messages; alias for '-o5'
    -q                 quiet: do not display progress bar during creating image file
    -f config_file     file: configuration file to be used
    -t status_file     tick: status file to be used
    -R days            Rotation: performs rotation for backup image files older then _days_

Configuration
=====
The configuration is predefined by the values of configuration parameters in the section
**\_config**. Each of configuration parameters begins with the prefix **CONFIG\_**. Here are
some of the most interesting ones. Change them reasonably and if you know, what you are doing.

#### CONFIG\_backup_dir
This parameter defines the backup folder. It is predefined to the **/var/backups/images**.
However, it should be just the symbolic link to the final backup folder usually outside the SD
card of the Raspberry Pi. For instance, it might be an external device or a folder in the NAS mounted
in */mnt* folder, e.g., */mnt/nas/images/<hostname\>*.

#### CONFIG\_backup_file_prefix
This parameter defines the prefix of the backup file's name. It is defaulted to the hostname
of the current operating system. It is useful for distinguishing backup files, if they are located
in the same target folder from more microcomputers.

#### CONFIG\_backup\_file_suffix
This parameter defines the extension of the backup file's name. It is defaulted to the **.img**
(including leading dot). If you prefer backup file names without extensions, just leave this parameter
blank.

#### CONFIG\_timestamp_format
This parameter defines formatting of the backup file timestamp included in its name. It is defaulted
to the pattern **YYYY-MM-DD\_HHhMIm**, e.g., 2013-12-31_23h59m. This pattern is expected in the backup
files names in the script _syncfilestimestamp.sh_.

#### CONFIG\_rotation_days
This parameter defines the time period for which the backup files are kept in the backup folder.
Older backup files than those days from the current time are deleted after the successful backup.

#### CONFIG_services
This array is the list of services, which are temporarily stopped during the backup process. The list
is defaulted to the most common services that are usually frequently writting to the SD card, so that
they should not be active during the backup process. Update or extend this array according to your
current situation, e.g., replace _apache2_ with current web server service.

#### CONFIG_sdhc
This parameter defines the device, which is the subject of the backup process. It is the SD card itself.
But it may be changed to other device, which you want to backup.

#### CONFIG\_block_size
This parameter defines the size of the block copied as a unit in the syntax for the utility *dd*.
It is defaulted to the value recommended for Raspberry Pi SD cards in several articles.

#### CONFIG\_level_logging
This parameter defines the level or intensity of logging to system log **user.log**. It takes
an integer parameter from the following list

 - `0` ... no logging to system log
 - `1` ... logging just error messages
 - `2` ... logging warning messages as well as all messages from previous logging levels
 - `3` ... logging information messages as well as all messages from previous logging levels
 - `4` ... logging all possible messages that can be logged

#### CONFIG\_level_verbose
This parameter defines the level of verbosity to the console. It takes an integer parameter
from the following list

 - `0` ... no messages
 - `1` ... just error messages
 - `2` ... messages for emailing as well as all messages from previous verbose levels
 - `3` ... information messages as well as all messages from previous verbose levels
 - `4` ... messages from essetial functions as well as all messages from previous verbose levels
 - `5` ... all possible messages

#### CONFIG_config
The path to a configuration file, which can substitute command line options and parameters.
It is read in the script as a shell script so you can abuse that fact if you so want to.
It should contain just configuration variables assignment that you want to overide in the form

    CONFIG_param=value

The configuration file should not contain any programmatic code in order not to change the behaviour
of the script.
In order to minimize the command line options and make the backing up more customizable,
the configuration file should contain configuration parameters for this assets:

  - Backup folder
  - Rotation days
  - List of suspending services

License
=====
This script is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
