#!/usr/bin/env bash
#
# NAME:
#   check_temp.sh - Check the Broadcom SoC temperature
#
# SYNOPSIS:
#   check_temp.sh [OPTION [ARG]]
#
# DESCRIPTION:
# Script checks the internal temperature of the CPU and warns or shuts down the system
# if temperature limits are exceeded.
# - Script has to be run under root privileges (sudo ...).
# - Script is supposed to run under cron.
# - Script logs to "user.log".
# - Script may write its working status into a status (tick) file if defined, what may
#   be considered as a monitoring heartbeat of the script especially then in normal conditions
#   it produces no output.
# - Status file should be located in the temporary file system (e.g., in the folder /run)
#   in order to reduce writes to the SD card.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#   in a configuration file declared in the command line.
# - In simulation mode the script ommits shutting down the system.
# - The halting (shutdown) temperature limit is the 95% (configurable)
#   of maximal temperature written in
#   /sys/class/thermal/thermal_zone0/trip_point_0_temp.
# - The warning temperature limit is the 80% (configurable) of that maximal temperature.
# - The current temperature is read from /sys/class/thermal/thermal_zone0/temp.
#
# OPTIONS & ARGS:
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
#   -S
#       Sensors. List all sensor parameters.
#   -1
#      Force warning. Simulate reaching warning temperature.
#   -2
#      Force error. Simulate reading exactly maximal temperature.
#   -3
#      Force fatal. Simulate exceeding shutdown temperature.
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
CONFIG_copyright="(c) 2014-2016 Libor Gabaj <libor.gabaj@gmail.com>"
CONFIG_version="0.6.1"
#
CONFIG_warning_perc=80                   # Percentage of maximal limit for warning - should be integer
CONFIG_shutdown_perc=95                  # Percentage of maximal limit for shutting down - should be integer
CONFIG_flag_print_sensors=0              # List sensor parameters flag
CONFIG_flag_force_warning=0              # Force warning temperature flag
CONFIG_flag_force_shutdown=0             # Force shutdown temperature flag
CONFIG_flag_force_maximum=0              # Force maximal temperature flag
# <- END _config

# <- BEGIN _sensors
# Board sensor temperature in milidegrees Celsius
SENSOR_temp_current=$(cat /sys/class/thermal/thermal_zone0/temp)
if [[ ${SENSOR_temp_current} -lt 100 ]]
then
	SENSOR_temp_current=$(echo ${SENSOR_temp_current} | awk '{printf("%d", $1 * 1000)}')
fi
SENSOR_temp_current_text=$(echo "Current temperature" $(echo ${SENSOR_temp_current} | awk '{printf("%.1f", $1 / 1000)}') "'C")

# Temperature technical limit
SENSOR_temp_maximal=$(cat /sys/class/thermal/thermal_zone0/trip_point_0_temp)
if [[ ${SENSOR_temp_maximal} -lt 100 ]]
then
        SENSOR_temp_maximal=$(echo "${SENSOR_temp_maximal}" | awk '{printf("%d", $1 * 1000)}')
fi
SENSOR_temp_maximal_text=$(echo "Maximal temperature" $(echo ${SENSOR_temp_maximal} | awk '{printf("%.1f", $1 / 1000)}') "'C")

# Temperature limit for warning
SENSOR_temp_warning=$(echo "${SENSOR_temp_maximal} ${CONFIG_warning_perc}" | awk '{printf("%d", $1 * $2 / 100)}')
SENSOR_temp_warning_text=$(echo "Warning temperature" $(echo ${SENSOR_temp_warning} | awk '{printf("%.1f", $1 / 1000)}') "'C")

# Temperature limit for shutdown
SENSOR_temp_shutdown=$(echo "${SENSOR_temp_maximal} ${CONFIG_shutdown_perc}" | awk '{printf("%d", $1 * $2 / 100)}')
SENSOR_temp_shutdown_text=$(echo "Shutdown temperature" $(echo ${SENSOR_temp_shutdown} | awk '{printf("%.1f", $1 / 1000)}') "'C")
# <- END _sensors

# -> BEGIN _functions

# @info:	Display usage description
# @args:	(none)
# @return:	(none)
# @deps:	(none)
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]]"
	echo "
Check temperature of the SoC and shutdown at overheating
over the shutdown temperature or warn at warning temperature.

Warning temperature is the percentage (${CONFIG_warning_perc}%) of maximal limit.
Shutdown temperature is the percentage (${CONFIG_shutdown_perc}%) of maximal limit.
$(process_help -o)
  -S			Sensors: List all sensor parameters.
  -1			Force warning: Simulate reaching warning temperature.
  -2			Force error: Simulate reading exactly maximal temperature.
  -3			Force fatal: Simulate exceeding shutdown temperature.
$(process_help -f)
"
}
# <- END _functions

# Process command line parameters
process_options $@
while getopts "${LIB_options}S123" opt
do
	case "$opt" in
	S)
		CONFIG_flag_print_sensors=1
		;;
	1)
		CONFIG_flag_force_warning=1
		;;
	2)
		CONFIG_flag_force_maximum=1
		;;
	3)
		CONFIG_flag_force_shutdown=1
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

init_script
process_folder -t "Status" -f "${CONFIG_status}"
show_configs

# Print sensor parameters
if [ $CONFIG_flag_print_sensors -eq 1 ]
then
	echo_text -hb -$CONST_level_verbose_none "List of sensor parameters:"
	echo_text -s -$CONST_level_verbose_none "${SENSOR_temp_current_text}"
	echo_text -s -$CONST_level_verbose_none "${SENSOR_temp_maximal_text}"
	echo_text -s -$CONST_level_verbose_none "${SENSOR_temp_shutdown_text}"
	echo_text -sa -$CONST_level_verbose_none "${SENSOR_temp_warning_text}"
fi

# -> Script execution
trap stop_script EXIT

# Log current temperature to syslog and status file
message="${SENSOR_temp_current_text}"
echo_text -h -$CONST_level_verbose_info "$message."
log_text -IS -$CONST_level_logging_info "$message"
if [ -n "$CONFIG_status" ]
then
	echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status'."
	echo_text -ISL -$CONST_level_verbose_none "$message." > "$CONFIG_status"
fi

# Warn if the temperature is between the warning and maximal limit
if [[ $SENSOR_temp_current -gt $SENSOR_temp_warning && $SENSOR_temp_current -lt $SENSOR_temp_shutdown || $CONFIG_flag_force_warning -eq 1 ]]
then
	message="${SENSOR_temp_current_text} is greater than ${SENSOR_temp_warning_text}"
	echo_text -e -$CONST_level_verbose_error "$message."
	log_text -WS -$CONST_level_logging_error "$message"
fi

# Report if current temperature is exactly equal to the maximal temperature
if [[ $SENSOR_temp_current -eq $SENSOR_temp_maximal || $CONFIG_flag_force_maximum -eq 1 ]]
then
	message="${SENSOR_temp_current_text} is equal to ${SENSOR_temp_maximal_text}"
	echo_text -e -$CONST_level_verbose_error "$message."
	log_text -ES -$CONST_level_logging_error "$message"
fi

# Shutdown system if the temperature is greater than maximal limit
if [[ $SENSOR_temp_current -gt $SENSOR_temp_shutdown && $SENSOR_temp_current -ne $SENSOR_temp_maximal || $CONFIG_flag_force_shutdown -eq 1 ]]
then
	message="${SENSOR_temp_current_text} is greater than ${SENSOR_temp_shutdown_text}"
	log_text -FS -$CONST_level_logging_error "$message"
	echo_text -e -$CONST_level_verbose_error "$message."
	# Halt the box
	message="Shutting down due to overheating$(dryrun_token)"
	echo_text -h -$CONST_level_verbose_error "$message."
	if [[ $CONFIG_flag_dryrun -eq 0 ]]
	then
		log_text -FS -$CONST_level_logging_error "$message"
		halt
	fi
fi

# End of script processed by TRAP
