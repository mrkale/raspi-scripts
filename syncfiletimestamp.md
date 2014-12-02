Synchronize file time with file timestamp
=====
The script is supposed to be used manually for interactive synchronizing
modification and creation time of files with timestamp in their names.
It is useful if backup files with timestamp in names have been moved to another
location without preserving modification time, but the rotating backup
has to be retained.

Name
=====
**syncfiletimestamp.sh** - synchronize file time with timestamp in name

Synopsis
=====
    syncfiletimestamp.sh [OPTION [ARG]] [FILE]
    syncfiletimestamp.sh [OPTION [ARG]] < FILELIST 
    ls file_pattern | ./syncfiletimestamp.sh [OPTION [ARG]]

Description
=====
Script reads timestamp from names of input files and changes their creation
and modification date and time accordingly, i.e., synchronizes file time with file timestamp.

- If there are no input files, the script reads file list from the standard input.
- If there is no standard input from pipe, it reads from console. Finish input by Ctrl+D.
- Script filters input files according to the timestamp pattern.
- The timestamp pattern is defined by the regular expression in a configuration parameter.
- Script has to be run under root privileges (sudo ...).
- All essential configuration parameters are defined in the section of configuration parameters.
  Their description is provided locally. Script can be configured by changing their values.
- In simulation mode the script provides only checks and does not change input files.

Example of a file with a timestamp in its name:

    hostname_2013-12-31_23h59m.img

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
    -L                 List: Display list of files that are being processed

Configuration
=====
The configuration is predefined by the values of configuration parameters in the section
**\_config**. Each of configuration parameters begins with the prefix **CONFIG\_**. Here are
some of the most interesting ones. Change them reasonably and if you know, what you are doing.

#### CONFIG\_file_pattern
This parameter defines the pattern for a timestamp in file names. It is composed as a regular
expression with date and time components in parentheses for backreferencing in the order - 
**Year, Month, Day, Hour, Minute**. It is defaulted to the regular expression:

    ^.*\([0-9]\{4\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\)_\([0-9]\{2\}\)h\([0-9]\{2\}\)m.*$

The backreferences are used at files processing for composing the timestamp for the command:

    touch -t

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

License
=====
This script is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
