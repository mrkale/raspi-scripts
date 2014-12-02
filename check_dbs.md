Check tables in MySQL databases
=====
The script is supposed to check database tables of type MyISAM, InnoDB, and Archive.
By default the script outputs just the error messages about corrupted tables, so that
it is suitable for periodic checking under cron.

Name
=====
**check_dbs.sh** - check tables in MySQL databases

Synopsis
=====
    check_dbs.sh [OPTION [ARG]]

Description
=====
Script checks tables in selected MySQL databases.

- Script is supposed to run under cron.
- Script logs to "user.log".
- Script may write its working status into a status (tick) file if defined, what may
  be considered as a monitoring heartbeat of the script especially then in normal conditions
  it produces no output.
- Status file should be located in the temporary file system (e.g., in the folder `/tmp`)
  in order to reduce writes to the SD card. 
- Script outputs corrupted tables into standard error output, if some have been detected.
- Script checks only database tables under engines MyISAM, InnoDB, and Archive.
- System databases are implicitly excluded from checking.
- All essential parameters are defined in the section of configuration parameters.
  Their description is provided locally. Script can be configured by changing
  values of them.
- Configuration parameters in the script can be overriden by the corresponding ones
	in a configuration file declared in the command line. The configuration file is read in
	as a shell script so you can abuse that fact if you so want to.
- Configuration file should contain only those configuration parameters
  that you want to override.

Options and arguments
=====
    -h                 help: show this help and exit
    -V                 Version: show version information and exit
    -c                 configs: print listing of all configuration parameters
    -l log_level       logging: level of logging intensity to syslog
                       0=none, 1=errors (default), 2=warnings, 3=info, 4=full
    -o verbose_level   output: level of verbosity
                       0=none, 1=errors (default), 2=mails, 3=info, 4=functions, 5=full
    -m                 mailing: display all processing messages; alias for '-o2'
    -v                 verbose: display all processing messages; alias for '-o5'
    -f config_file     file: configuration file to be used
    -t status_file     tick: status file to be used
    -u user            user: name of the database user
    -p password        password: password of the database user
    -d database        database: included database; option can be repeated for db list
    -1                 Force corruption: Simulate the first table of every database as corrupted.

Configuration
=====
The configuration is predefined by the values of configuration parameters in the section
**\_config**. Each of configuration parameters begins with the prefix **CONFIG\_**. Here are
some of the most interesting ones. Change them reasonably and if you know, what you are doing.

#### CONFIG\_db\_excluded_dbs
This is a list of databases excluded from checking. Implicitly the list is populated with
following system databases, but it may be extended with other databases.

- information_schema
- performance_schema
- mysql

#### CONFIG\_db\_included_dbs
This is a list of databases that are going to be checked. If the list is empty, all 
databases are used except excluded ones. However, this list can be populated with only
databases for checking either directly in this configuration parameter as an array or
from command line by repeating usage of enumerated databases.

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
In order to minimize the command line options and secure access credentials to a database server, 
the configuration file should contain configuration parameters for this assets:

  - User name
  - User password
  - Included databases
 
License
=====
This script is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
