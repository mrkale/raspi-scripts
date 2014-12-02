Backup SD card root file system
===============================
The script is supposed to be used for backing up root file system 
to a backup folder with help of ***rsync*** utility. It may be used manually
or under cron.

Name
====
**backupsd.sh** - backup root file system of SD card to a backup folder

Synopsis
========
    backupsd.sh [OPTION [ARG]] [backup_folder]

Description
===========
Script makes a files and folders backup of the root file system of SD card
to a backup folder with help of utility 'rsync'.

- Script has to be run under root privileges (sudo ...).
- Script can be run manually or under cron.
- Backup folder should not be a CIFS file system, because the symbolic link
  cannot be created on it.
- The first backup to particular backup folder takes longer (couple of minutes), while
  subsequent backups are just differential and may take much less time.
- Some folders from file system have to be excluded from backup (virtual and system ones)
  by writing them to the exclusion file declared in command line as a argument of
  corresponding command line option. The exclusion file line for particular folder
  should be in the form: `/folder/*`. It ensures that the excluded folder is created
  in the backup folder, but as empty one.
- If there is exclusion file defined neither in the command line nor a configuration file,
  the script creates new exclusion file `backupsd.sh.exclude.lst` in the same folder
  as the script is located in with default content. It is recommended to move that file
  to some common location, e.g., `/usr/local/etc`.
- Log file name is composed of current hostname, current script name, and current datetime.
- Log files are located by default in the base (superordinate) folder to the backup folder,
  so that they do not mess the original content of the file system. However, the folder
  of the log files can be declared in command line or a configuration file.
- Status file should be located in the temporary file system (e.g., in the folder `/tmp`)
  in order to reduce writes to the SD card. 
- All essential parameters are defined in the section of configuration parameters.
  Their description is provided locally. Script can be configured by changing values of them.
- Configuration parameters in the script can be overriden by the corresponding ones
  in a configuration file declared in the command line. The configuration file is read in
  as a shell script so you can abuse that fact if you so want to.
- Configuration file should contain only those configurtion parameters that you want to override.
- Script performes rotating backup of log files, i.e., it deletes obsolete log files older than
  predefined number of days (default 30) before the current time of the backup process.
  This number can be redefined by corresponding command line option.
- In simulation mode the script neither backs up anything nor potentially creates backup folder,
  just creates a log file.

Example of log file (the placeholder *<hostname\>* is replaced
with real box hostname):

    <hostname>_backupsd.sh_2014-10-01_23h59m.log

Options and arguments
=======
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
    -f config_file     file: configuration file to be used
    -t status_file     tick: status file to be used
    -E exclusion_file  Exclusion: file with list of excluded files from backup
    -L log_dir         Logger: log folder defaulted to base folder of the backup folder
    -R days            Rotation: performs rotation for log files older then _days_

Configuration
=============
The configuration is predefined by the values of configuration parameters in the section
**\_config**. Each of configuration parameters begins with the prefix **CONFIG\_**. Here are
some of the most interesting ones. Change them reasonably and if you know, what you are doing.

#### CONFIG\_backup_dir
This parameter defines the backup folder. It is not predefined, so that it has to be defined
either in the command line or in a configuration file.

#### CONFIG\_log_dir
The path to a folder with log files. By default it is taken from base folder of the backup folder, 
i.e., its subordinate folder, if there is a log folder defined neither in the command line nor
a configuration file.

#### CONFIG\_log_prefix
This parameter defines the prefix of the log file's name. It is defaulted to the hostname
of the current operating system and the name of this script. It is useful for distinguishing
log files if they are located in the same base folder for more microcomputers.

#### CONFIG\_log_suffix
This parameter defines the extension of the log file's name. It is defaulted to the **.log**
(including leading dot). If you prefer log file names without extensions, just leave this parameter
blank.

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

#### CONFIG\_timestamp_format
This parameter defines formatting of the log file timestamp included in its name. It is defaulted
to the pattern **YYYY-MM-DD\_HHhMIm**, e.g., 2014-10-01_23h59m.

#### CONFIG\_rotation_days
This parameter defines the time period for which the log files are kept in the base folder.
Older log files than those days from the current time are deleted after the successful backup.
It is defaulted to **30 days**, but may be overriden from the command line or a configuration file.

#### CONFIG\_options_rsync
This parameter defines the options for backup utility 'rsync' except defining exclusion file.
Do not change the parameter if you do not exactly know what you are doing.

#### CONFIG_exclude
The path to an exclusion file with folders and files that should be excluded from the backup.
If there is exclusion file defined neither in the command line nor a configuration file,
the script creates new exclusion file `backupsd.sh.exclude.lst` in the same folder as the script is located in with
default content. It is recommended to move that file to some common location, e.g., `/usr/local/etc`. For each excluded folder, or a file mask, or just a file a separate line
has to be written in the exclusion file, usually in the form: `/folder/*`. It ensures
that an excluded folder is created in the backup folder, but as empty one.

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
  - Exclusion file
  - Logging folder
  - Rotation days
  

License
=======
This script is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
