#!/usr/bin/env bash
#
# NAME:
#   iot_initialstate.sh - Record data remotely to IoT service Initial State
#
# SYNOPSIS:
#   iot_initialstate.sh [OPTION [ARG]]
#
# DESCRIPTION:
# Script measures internal temperature of the CPU as well as temperatures from DS18B20 sensors.
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
#
# LICENSE:
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#

#LIB_options_exclude=( 't' )
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
CONFIG_version="0.1.0"
CONFIG_commands_run=('curl') # List of commands for full running
#
declare -A CONFIG_sensors_soc=([0]="SoC")	# stream[0]
declare -A CONFIG_sensors_ds18b20=([28-000001b46e0e]="Lobby")	# stream[Address]
# declare -A CONFIG_sensors_ds18b20=([28-000001b46e0e]="Room1" [28-000001b46e1e]="Room2")	# stream[Address]
CONFIG_initialstate_url="https://groker.initialstate.com/batch_logs"
CONFIG_initialstate_apikey="baGwkZMbLpeo4QtEFRKRjksILn8QzjXE"
CONFIG_initialstate_bucket_id="03fd6631-01b0-49ce-9ca7-c7881e3cca5f"
CONFIG_initialstate_bucket_name="TestBucketLG"
CONFIG_flag_print_sensors=0              # List sensor parameters flag
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
	echo "${CONFIG_script} [OPTION [ARG]]"
	echo "
Record temperatures (internal SoC and from sensors) to Initial State IoT service.
$(process_help -o)
  -S			Sensors: List sensor array 'temperature[fieldnum]'
  -A apikey		Apikey: InitialState api write key
$(process_help -f)
"
}

# @info:	Read SoC temperature in milidegrees Celsius
# @args:	Associative array temp[fieldnum]
# @return:	System temperature
# @deps:	none
read_soc () {
	local temp stream
	temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
	stream=${CONFIG_sensors_soc[0]}
	local -A tempArray=(["$stream"]=$temp)
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
	local temp address stream
	local -A tempArray=()
	for file in $(ls /sys/bus/w1/devices/28-*/w1_slave 2>/dev/null)
	do
		address=${file%/*}
		address=${address##*/}
		temp=$(cat $file | tr "\\n" " " | grep "YES")
		temp=${temp##*t=}
		temp=${temp%% }
		stream=${CONFIG_sensors_ds18b20[$address]}
		if [[ -n "$stream" && -n "$temp" ]]
		then
			tempArray+=(["$stream"]=$temp)
		fi
	done
	tempArray=$(declare -p tempArray)
	tempArray=${tempArray#*=}
	tempArray=${tempArray//\'}
	printf "$tempArray"
}

# @info:	Send data to InitialState service
# @args:	none
# @return:	curl exit code
# @deps:	global SENSOR_temps variable
write_initialstate () {
	local temp objdata reqdata result=0
	# Compose data part of the HTTP request
	for stream in ${!SENSOR_temps[@]}
	do
		temp=${SENSOR_temps[$stream]}
		temp="${temp// }"
		if [[ -n "$temp" && ${#temp} -ge 3 ]]
		then
			temp="${temp:0:${#temp}-3}.${temp:${#temp}-3}"
			objdata=""
			# Bucket name
			objdata+="${objdata:+,}\"b\":\"$CONFIG_initialstate_bucket_name\""
			# Bucket id
			objdata+="${objdata:+,}\"tid\":\"$CONFIG_initialstate_bucket_id\""
			# Stream name
			objdata+="${objdata:+,}\"sn\":\"$stream\""
			# Stream epoche time
			objdata+="${objdata:+,}\"e\":$(date +%s)"
			# Stream value
			objdata+="${objdata:+,}\"v\":${temp}"
			# Add to JSON array
			reqdata+="${reqdata:+,}{$objdata}"
		fi
	done
	# Process data part
	if [[ -n "$reqdata" ]]
	then
		reqdata="[$reqdata]"
	fi
	# Compose HTTP request
	echo_text -f -$CONST_level_verbose_function "Logging to InitialState$(dryrun_token) ... $reqdata"
	if [[ $CONFIG_flag_dryrun -eq 0 && -n "$reqdata" ]]
	then
		$(curl \
			--header "Content-Type: application/json" \
			--header "X-IS-ClientKey: ${CONFIG_initialstate_apikey}" \
			--request POST \
			--data "$reqdata" \
		"${CONFIG_initialstate_url}" 2>/dev/null) 
		result=$?
		# Write to status log
		if [ -n "$CONFIG_status" ]
		then
			msg="InitialState code=$result."
			echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status' ... $msg"
			echo_text -ISL -$CONST_level_verbose_none "$msg" > "$CONFIG_status"
		fi
	fi
	return $result
}
# <- END _functions

# Process command line parameters
process_options $@
while getopts "${LIB_options}SA:" opt
do
	case "$opt" in
	S)
		CONFIG_flag_print_sensors=1
		;;
	A)
		CONFIG_initialstate_apikey=$OPTARG
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

# Check API key presence
echo_text -hp -$CONST_level_verbose_info "Checking API key$(dryrun_token) ... "
if [[ $CONFIG_flag_dryrun -eq 1 || -n "$CONFIG_initialstate_apikey" ]]
then
	echo_text -$CONST_level_verbose_info "ok. Proceeding."
else
	echo_text -$CONST_level_verbose_info "not defined. Exiting."
	fatal_error "No API key defined."
fi

process_folder -t "Status" -f "${CONFIG_status}"
show_configs

# -> Script execution
trap stop_script EXIT

# Read system and external temperature sensors in milidegrees Celsius
declare -A SENSOR_temps+=$(read_soc)
declare -A SENSOR_temps+=$(read_ds18b20)

# Print sensor parameters
if [[ $CONFIG_flag_print_sensors -eq 1 ]]
then
	echo_text -hb -$CONST_level_verbose_none "Sensors array 'temp_in_milidegCelsius[FieldNum]':"
	echo_text -sa -$CONST_level_verbose_none "$(declare -p SENSOR_temps)"
fi

# Write temperature to InitialState
write_initialstate

# End of script processed by TRAP
