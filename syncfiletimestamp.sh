#!/bin/bash
#
# Script reads datetime stamp from names of files provisioned as arguments (list of files) to the script
# and changes their creation and modification date and time accordingly.
# If there are no arguments, the script reads file list from the standard input.
# The pattern for extracting datetime components from a file name is defined by regular expression
# in configuration variable.
#
# Example:
# - Files given as input parameters
#		synchfiletimestamp.sh /path/to/files/file*.txt
# - Files given as standard input
# 		find /path/to/files/file*.txt -type f | synchfiletimestamp.sh
#
# NAME:
#   syncfiletimestamp.sh - synchronize file modification time with timestamp in name
#
# SYNOPSIS:
#   syncfiletimestamp.sh [OPTION [ARG]] [FILE]
#   syncfiletimestamp.sh [OPTION [ARG]] < FILELIST
#   ls filepattern | syncfiletimestamp.sh [OPTION [ARG]]
#
# DESCRIPTION:
# Script reads timestamp from names of input files and changes their creation
# and modification date and time accordingly, i.e., synchronizes file time with file timestamp.
# - If there are no input files, the script reads file list from the standard input.
# - If there is no standard input from pipe, it reads from console. Finish input by Ctrl+D.
# - Script filters input files according to the timestamp pattern.
# - The timestamp pattern is defined by the regular expression in a configuration parameter.
# - Script has to be run under root privileges (sudo ...).
# - All essential configuration parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing their values.
# - In simulation mode the script provides only checks and does not change input files.
#
# Example of a file with a timestamp in its name:
#   hostname_2013-12-31_23h59m.img
#
# OPTIONS:
#   -h
#       Help. Show usage description and exit.
#   -s
#       Simmulation. Perform dry run just with output messages and log files.
#   -V
#       Version. Show version and copyright information and exit.
#   -c
#       Configs. Print listing of all configuration parameters.
#   -l LoggingLevel
#		Logging. Level of logging intensity to syslog
#		0=none, 1=errors (default), 2=warnings, 3=info, 4=full
#   -o VerboseLevel
#       Output. Level of verbose intensity.
#		0=none, 1=errors, 2=mails, 3=info (default), 4=functions, 5=full
#   -m
#       Mailing. Display processing messages suitable for emailing from cron.
#       It is an alias for '-o2'.
#   -v
#       Verbose. Display all processing messages.
#       It is an alias for '-o5'.
#   -f ConfigFile
#       File. Configuration file for overriding default configuration parameters.
#   -t StatusFile
#       Tick. File for writing working status of the script.
#       Should be located in temporary file system.
#   -L
#       List. Display list of files that are being processed.
#
# LICENSE:
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#

# Load library file
LIB_name="scripts_lib"
for lib in "$LIB_name"{.sh,}
do
	LIB_file="$(command -v "$lib")"
	if [ -z "$LIB_file" ]
	then
		LIB_file="$(dirname $0)/$lib"
	fi
	if [ -f "$LIB_file" ]
	then
		source "$LIB_file"
		unset -v LIB_name LIB_file
		break
	fi
done
if [ "$LIB_name" ]
then
	echo "!!! ERROR -- No file found for library name '$LIB_name'."  1>&2
	exit 1
fi

# -> BEGIN _config
CONFIG_copyright="(c) 2013-2014 Libor Gabaj <libor.gabaj@gmail.com>"
CONFIG_version="2.0.0"
CONFIG_commands=('grep' 'sed' 'touch')

# Pattern for parsing datetime. Datetime components are enclosed in parentheses in the order - Year Month Day Hour Minute. 
CONFIG_file_pattern="^.*\([0-9]\{4\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\)_\([0-9]\{2\}\)h\([0-9]\{2\}\)m.*$"
CONFIG_flag_filelist=0	# Default no file list output
# <- END _config

# -> BEGIN _functions

# @info:	Displays usage description
# @args:	(none)
# @return:	(none)
# @deps:	(none)
show_help () {
	echo "
$(basename $0) [OPTION [ARG]] filelist
$(basename $0) [OPTION [ARG]] < file_with_filelist
ls file_pattern | ./$(basename $0) [OPTION [ARG]]

Synchronize modification time of files with timestamp incorporated in their names.

Without any input file list it is awaited from the standard input. Please press
Ctrl+D to end the input after writing file specifications.
$(process_help -o)
 -L			List: display list of files that are being processed
$(process_help -f)
"
}
# <- END _functions

# Process input arguments
process_options $@
while getopts "${LIB_options}L" opt
do
	case "$opt" in
	L)
		CONFIG_flag_filelist=1
		;;
	\?)
		msg="Unknown option '-$OPTARG'."
		fatal_error "$msg $help"
		;;
	:)	
		case "$OPTARG" in
		*)
			msg="Missing argument for option '-$OPTARG'."
			;;
		esac
		fatal_error "$msg $help"
	esac
done

# Process non-option arguments
shift $(($OPTIND-1))
if [ -n "$1" ]
then
	INPUT=($(ls $@ 2>/dev/null))
else
    # Take file list from standard input
    INPUT=($(</dev/stdin))
fi

init_script
process_folder -t "Status" -f "${CONFIG_status}"
show_configs

# -> Script execution
trap stop_script EXIT
if [ -n "$CONFIG_status" ]
then
	echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status'."
	echo_text -ISL -$CONST_level_verbose_none "Retiming files ...  ${#INPUT[@]}." > "$CONFIG_status"
fi

# Filter input files by matching pattern
INPUT=($(ls ${INPUT[@]} | grep "${CONFIG_file_pattern}"))

# Process files
echo_text -h -$CONST_level_verbose_mail "Number of files to process ${#INPUT[@]}."
for file in ${INPUT[@]}
do
	if [ ! -f "${file}" ]
	then
		continue
	fi
	# Create "touch -t" datetime format from sed output
	TIMESTAMP=$(echo $(basename "${file}") | sed "s/${CONFIG_file_pattern}/\1\2\3\4\5/")
	if [ $CONFIG_flag_filelist -eq 1 ]
	then
		echo_text -s -$CONST_level_verbose_mail "%s -> timestamp '%s'$(dryrun_token)." ${file} ${TIMESTAMP}
	fi
    # Synchronize modification time with timestamp
	if [ $CONFIG_flag_dryrun -eq 0 ]
	then
		touch -t "${TIMESTAMP}" "${file}"
	fi
done

# End of script processed by TRAP
