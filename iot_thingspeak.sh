#!/usr/bin/env bash
#
# NAME:
#   iot_thingspeak.sh - Record data remotely to IoT service ThingSpeak and localy to RRD
#
# SYNOPSIS:
#   iot_thingspeak.sh [OPTION [ARG]] [RRD_file]
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
CONFIG_copyright="(c) 2014 Libor Gabaj <libor.gabaj@gmail.com>"
CONFIG_version="0.2.0"
CONFIG_commands=('rrdtool') # List of commands for full running
CONFIG_commands_run=('curl') # List of commands for full running
#
CONFIG_fieldnum_min=1
CONFIG_fieldnum_max=8
declare -A CONFIG_sensors_soc=([0]=1)	# fieldnum[0]
declare -A CONFIG_sensors_ds18b20=([28-*]=2)	# fieldnum[Address]
# declare -A CONFIG_sensors_ds18b20=([28-000001b46e0e]=2 [28-000001b46e1e]=3 [28-000001b46e2e]=4)	# fieldnum[Address]
CONFIG_thingspeak_url="https://api.thingspeak.com/update"
CONFIG_thingspeak_apikey=""
CONFIG_flag_print_sensors=0              # List sensor parameters flag
CONFIG_rrd_file="${CONFIG_script%\.*}.rrd"	# Round Robin Database file
CONFIG_rrd_step=300	# Round Robin Database base data feeding interval
CONFIG_rrd_hartbeat=2	# Round Robin Database hartbeat interval as a multiplier of the step
# <- END _config

# -> BEGIN _sensors
declare -A SENSOR_temps
# -> END _sensors

# -> BEGIN _functions

# @info:	Display usage description
# @args:	(none)
# @return:	(none)
# @deps:	(none)
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]] [RRD_file]"
	echo "
Record temperatures (internal SoC and from sensors) to ThingSpeak IoT service
and into local Round Robin Database. Default RRD is '$(basename ${CONFIG_script} .sh).rrd'
in the folder of the script.
$(process_help -o)
  -S			Sensors: List sensor array 'temperature[fieldnum]'
  -A apikey		Apikey: ThingSpeak api write key
  -I seconds		Interval: Base interval of feeding data to RRD
$(process_help -f)
"
}

# @info:	Read SoC temperature in milidegrees Celsius
# @args:	Associative array temp[fieldnum]
# @return:	System temperature
# @deps:	none
read_soc () {
	local temp fieldnum
	temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
	fieldnum=${CONFIG_sensors_soc[0]}
	local -A tempArray=([$fieldnum]=$temp)
	tempArray=$(declare -p tempArray)
	tempArray=${tempArray#*=}
	tempArray=${tempArray//\'}
	printf "$tempArray"
}

# @info:	Read DS18B20 temperatures in milidegrees Celsius
# @args:	none
# @return:	Associative array temp[fieldnum]
# @deps:	none
read_ds18b20 () {
	local temp address fieldnum
	local -A tempArray=()
	for file in $(ls /sys/bus/w1/devices/28-*/w1_slave 2>/dev/null)
	do
		address=${file%/*}
		address=${address##*/}
		temp=$(cat $file | tr "\\n" " " | grep "YES")
		temp=${temp##*t=}
		temp=${temp%% }
		fieldnum=${CONFIG_sensors_ds18b20[$address]}
		if [ -n "$fieldnum" ]
		then
			tempArray+=([$fieldnum]=$temp)
		fi
	done
	tempArray=$(declare -p tempArray)
	tempArray=${tempArray#*=}
	tempArray=${tempArray//\'}
	printf "$tempArray"
}

# @info:	Send data to ThingSpeak service
# @args:	none
# @return:	curl exit code
# @deps:	global SENSOR_temps variable
write_thingspeak () {
	local temp reqdata result=0
	# Compose data part of the HTTP request
	for fieldnum in ${!SENSOR_temps[@]}
	do
		if [[ $fieldnum -ge $CONFIG_fieldnum_min && $fieldnum -le CONFIG_fieldnum_max ]]
		then
			temp=${SENSOR_temps[$fieldnum]}
			temp="${temp// }"
			if [[ -n "$temp" && ${#temp} -ge 3 ]]
			then
				temp="${temp:0:${#temp}-3}.${temp:${#temp}-3}"
				reqdata+="&field${fieldnum}=${temp}"
			fi
		fi
	done
	# Process data part
	if [[ -n "$reqdata" ]]
	then
		reqdata="${reqdata:1}"
	fi
	# Compose HTTP request
	echo_text -f -$CONST_level_verbose_function "Logging to ThingSpeak$(dryrun_token) ... $reqdata"
	if [[ $CONFIG_flag_dryrun -eq 0 && -n "$reqdata" ]]
	then
		printf -v message "%s" $(curl \
			--header "THINGSPEAKAPIKEY: ${CONFIG_thingspeak_apikey}" \
			--request GET \
			--data "$reqdata" \
		"${CONFIG_thingspeak_url}" 2>/dev/null)
		# Error detection
		if [[ $message -eq 0 ]]
		then
			result=1
		fi
		# Write to status log
		if [ -n "$CONFIG_status" ]
		then
			msg="Sample no. ${message} to ThingSpeak."
			echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status' ... $msg"
			echo_text -ISL -$CONST_level_verbose_none "$msg" > "$CONFIG_status"
		fi
	fi
	return $result
}

# @info:	Create RRD file
# DS: temperature in milidegrees Celsius
#	System
#	DS18B20 no.1 - room
# RRA:
#	Read values for last 6 hours
#	Hour averages for last 7 days
#	Qoarter averages for last 30 days
#	Daily maximals for last 7 days
#	Daily maximals for last 30 days
#	Daily maximals for last 180 days
#	Daily minimals for last 7 days
#	Daily minimals for last 30 days
#	Daily minimals for last 180 days	
# @args:	none
# @return:	none
# @deps:	none
create_rrd_file () {
	local dslist
	echo_text -f -$CONST_level_verbose_function "Creating RRD file '${CONFIG_rrd_file}' with data streams:"
	for (( fieldnum=1; fieldnum<=${#SENSOR_temps[@]}; fieldnum++ ))
	do
		case "$fieldnum" in
		1)
			dslist+=" DS:temp_soc:GAUGE:$(( ${CONFIG_rrd_step} * ${CONFIG_rrd_hartbeat} )):20000:90000"
			;;
		2)
			dslist+=" DS:temp_ds01:GAUGE:$(( ${CONFIG_rrd_step} * ${CONFIG_rrd_hartbeat} )):0:40000"
			;;
		esac
	done
	echo_text -s -$CONST_level_verbose_function "${dslist## }"
	# Create RRD
	rrdtool create "${CONFIG_rrd_file}" \
	--step ${CONFIG_rrd_step} \
	--start -${CONFIG_rrd_step} \
	${dslist} \
	RRA:AVERAGE:0.5:1:72 \
	RRA:AVERAGE:0.5:12:168 \
	RRA:AVERAGE:0.5:72:120 \
	RRA:MAX:0.5:288:7 \
	RRA:MAX:0.5:288:30 \
	RRA:MAX:0.5:288:180 \
	RRA:MIN:0.5:288:7 \
	RRA:MIN:0.5:288:30 \
	RRA:MIN:0.5:288:180
}
# <- END _functions

# Process command line parameters
process_options $@
while getopts "${LIB_options}SA:I" opt
do
	case "$opt" in
	S)
		CONFIG_flag_print_sensors=1
		;;
	A)
		CONFIG_thingspeak_apikey=$OPTARG
		;;
	I)
		CONFIG_rrd_step=$OPTARG
		;;
	\?)
		msg="Unknown option '-$OPTARG'."
		fatal_error "$msg $help"
		;;
	:)
		case "$OPTARG" in
		A)
			msg="Missing API key for option '-$OPTARG'."
			;;
		I)
			msg="Missing RRD base interval for option '-$OPTARG'."
			;;
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
	CONFIG_rrd_file="$1"
fi
init_script

# Check API key presence
echo_text -hp -$CONST_level_verbose_info "Checking API key$(dryrun_token) ... "
if [[ $CONFIG_flag_dryrun -eq 1 || -n "$CONFIG_thingspeak_apikey" ]]
then
	echo_text -$CONST_level_verbose_info "ok. Proceeding."
else
	echo_text -$CONST_level_verbose_info "not defined. Exiting."
	fatal_error "No API key defined."
fi

process_folder -t "Status" -f "${CONFIG_status}"
process_folder -t "RRD" -fce "${CONFIG_rrd_file}"
show_configs

# -> Script execution
trap stop_script EXIT

# Read system and external temperature sensors in milidegrees Celsius
declare -A SENSOR_temps+=$(read_soc)
declare -A SENSOR_temps+=$(read_ds18b20)

# Create RRD
if [ ! -f "$CONFIG_rrd_file" ]
then
	echo_text -h -$CONST_level_verbose_info "RRD file '$CONFIG_rrd_file' does not exist. Creating."
	create_rrd_file
fi

# Write temperature into RRD
RRDcmd="rrdtool update ${CONFIG_rrd_file} N"
for temp in ${SENSOR_temps[@]}
do
	RRDcmd+=":${temp}"
done
echo_text -h -$CONST_level_verbose_info "RRD command for storing temperature in milidegrees Celsius:"
echo_text -s  -$CONST_level_verbose_info "$RRDcmd"
$($RRDcmd)
RESULT=$?
if [ $RESULT -ne 0 ]
then
	msg="RRD update failed with error code '$RESULT'."
	echo_text -e  -$CONST_level_verbose_error "$msg"
	log_text  -ES -$CONST_level_logging_error "$msg"
fi

# Print sensor parameters
if [[ $CONFIG_flag_print_sensors -eq 1 ]]
then
	echo_text -hb -$CONST_level_verbose_none "Sensors array 'temp_in_milidegCelsius[FieldNum]':"
	echo_text -sa -$CONST_level_verbose_none "$(declare -p SENSOR_temps)"
fi

# Write temperature to ThingSpeak
write_thingspeak

# End of script processed by TRAP
