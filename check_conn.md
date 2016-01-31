Check network connection to router and internet
=====
The script is supposed to be run under cron. It checks if a network
connection to the router as well as to the internet is active and working.
It sends the status of connection to Google Analytics and logs it into
the system log as well. If the connection is permanently disconnected,
it either restarts wlan interface or reboots the system.

Name
====
**check_conn.sh** - Check network connection to router and internet

Synopsis
=====
    check_conn.sh [OPTION [ARG]] [log_file]

Description
=====
Script checks if a network connection to the router as well as to the internet is active and working.
It sends the status of connection to Google Analytics and logs it into the system log as well.

- Script has to be run under root privileges (sudo ...).
- Script is supposed to run under cron.
- Script marks connection status in Google Analytics as an event.
- Script logs connection status to `user.log`.
- Script may write its working status into a status (tick) file if defined, what may
  be considered as a monitoring heartbeat of the script especially then in normal conditions
  it produces no output.
- Status file should be located in the temporary file system (e.g., in the folder `/tmp`)
  in order to reduce writes to the SD card. 
- All essential parameters are defined in the section of configuration parameters.
  Their description is provided locally. Script can be configured by changing values of them.
- Configuration parameters in the script can be overriden by the corresponding ones
  in a configuration file declared in the command line.
- For security reasons the Google Analytics tracking and client ids should be written
  only in configuration file. Putting them to a command line does not prevent them
  to be revealed by cron in email messages as a subject.
- If the Google Analytics tracking or client id is empty, the script does not send
  events to Google Analytics as well as in simulation mode.

Options and arguments
=====
    -h                 help: show this help and exit
    -s                 simulate: perform dry run without writing to Google Analytics
    -V                 Version: show version information and exit
    -c                 configs: print listing of all configuration parameters
    -l log_ level      logging: level of logging intensity to syslog
                       0=none, 1=errors (default), 2=warnings, 3=info, 4=full
    -o verbose_level   output: level of verbosity
                       0=none, 1=errors (default), 2=mails, 3=info, 4=functions, 5=full
    -m                 mailing: display all processing messages; alias for '-o2'
    -v                 verbose: display all processing messages; alias for '-o5'
    -f config_file     file: configuration file to be used
    -t status_file     tick: status file to be used
    -T TID             Tracking: Google Analytics tracking id (UA-XXXX-Y)
    -C CID             Client: Google Analytics client id (UUID v4)
    -I                 Internal: Check only internal connection
    -R interface,restart_fails,reboot_fails
                       Recovery: Comma separated
                       - Interface used for connection and to be restarted,
                       - Number of internal connection fails to restart interface,
                       - Number of internal connection fails to reboot system
                       e.g., wlan0,3,12. Negative or zero number supresses restarting
                       or rebooting altogether.
    -1                 Force internal failure: Pretend failed internal connection
    -2                 Force external failutre: Pretend failed external connection
  
Configuration
=====
The configuration is predefined by the values of configuration parameters in the script's
section **\_config**. Each of configuration parameters begins with the prefix **CONFIG\_**.
Here are some of the most interesting ones. Change them reasonably and if you know, what
you are doing.

The configuration parameters can be overriden by corresponding ones, if they are present
in the configuration file declared by an argument of the option "**-f**". Finally some of them
may be overriden by respective command line options. So the precedence priority
of configuration parameters is as follows where the latest is valid:

- Script
- Command line option
- Configuration file

#### CONFIG_pings
Number of pings to test an interface or an internet domain. Default value is *4*.

#### CONFIG\_ga_tid
Google Analytics tracking id. For security reason it should be written in a configuration
file. Putting it to the input argument of the option __-T__ does not prevent it to be revealed
by crontab in email messages as a subject.

#### CONFIG\_ga_cid
Google Analytics client id if form of UUID version 4 (random). For security reason
it should be written in a configuration file. Putting it to the input argument
of the option __-C__ does not prevent it to be revealed by crontab in email messages
as a subject.

#### CONFIG\_log_file
Error log file for temporary storing variables about a serie of failed network connections.
If the connection is restored, this file is deleted.

#### CONFIG\_ifc
The interface used for network connection. Default value is `eth0`, but usually it will be `wlan0`.
The current interface can be read from the command `ifconfig`.

#### CONFIG\_fails_restart
The number of connection failures to a router (gateway) after which an interface is restarted.
If restarting fails and the interface is still disconnected, the script restarts it every that 
number of connection failures. If the number is zero or negative, the interface is never restarted.
So that the number 0 is the default value and appropriate value should be defined in command line option
or a configuration file. It is recommended to use this number in conjunction with cron time period
in order to achieve some reasonable time of interface restarting. For instance, if the script is
launched by cron every 5 minutes, the fails number 3 means restarting the interface every three failures,
i.e., every 15 minutes.

#### CONFIG\_fails_reboot
The number of connection failures to a router (gateway) after which the operating system is rebooted.
If interface restart fails and an interface is still disconnected, the script reboots the system every that 
number of connection failures. If the number is zero or negative, the system is never rebooted. So that
the number 0 is the default value and appropriate value should be defined in command line option or a configuration
file. It is recommended to use this number in conjunction with cron time period in order to achieve some
reasonable time of system rebooting. For instance, if the script is launched by cron every 5 minutes, 
the fails number 12 means rebooting the system every hour.

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
In order to minimize the command line options and secure access credentials to Google Analytics, 
the configuration file should contain configuration parameters for this assets:

  - Google Analytics parameters
	- Google IP
	- Interface parameteres

License
=====
This script is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
