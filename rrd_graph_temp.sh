#!/usr/bin/env bash
#
# NAME:
#   rrd_graph_temp.sh - Generating temperature graphs from RRD
#
# SYNOPSIS:
#   rrd_graph_temp.sh [OPTION [ARG]] RRD_file [Graph_dir]
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
CONFIG_version="0.@.0"
CONFIG_commands=('rrdtool' 'chown') # List of commands for full running
#
CONFIG_rrd_file="${CONFIG_script%\.*}.rrd"	# Round Robin Database file
CONFIG_graph_dir=""	# Target folder for storing graph pictures
CONFIG_graph_ext="png"	# Graph picture file extension
CONFIG_graph_owner="www-data"	# Graph picture file owner to set after generation
CONFIG_graph_group="www-data"	# Graph picture file group to set after generation
# <- END _config

# -> BEGIN _functions

# @info:	Display usage description
# @args:	(none)
# @return:	(none)
# @deps:	(none)
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]] RRD_file [Graph_dir]"
	echo "
Generate PNG temperature graphs from Round Robin Database.
Default graph folder is folder containing the RRD.
$(process_help -o)
  -O owner		Owner: owner of the graph files to set (default '$CONFIG_graph_owner')
  -G group		Group: group of the graph files to set (default '$CONFIG_graph_group')
$(process_help -f)
"
}

# @info:	Create RRD graph
# @opts:	-t title ... name of a graph prefixed with hostname in uppercase (default none)
#			-d data  ... name of the DS variable in RRD
#			-l label ... descriptive name of the DS variable (default "Temperature")
#			-c color ... color of the line in pattern RRGGBB (default "FF0000")
#			-w width ... width of the line in pixels (default 1)
#			-s start ... start AT-STYLE time expression (default "-1d")
# @args:	none
# @return:	none
# @deps:	none
create_graph_line_single () {
	local file data vname
	local system="$(hostname)" unit="°C" time="-1d" width="1"
	local title="${system^^*}" label="Temperature" color="FF0000"
	local OPTIND opt
	# Process input parameters
	while getopts ":t:d:l:c:s:w:" opt
	do
		case "$opt" in
		t)
			title+=" - $OPTARG"
			;;
		d)
			data="$OPTARG"
			vname="${data}_01"
			;;
		l)
			label="$OPTARG"
			;;
		c)
			color="$OPTARG"
			;;
		s)
			time="$OPTARG"
			;;
		w)
			width="$OPTARG"
			;;
		:)
			msg="Missing argument for option '-$OPTARG'."
			fatal_error "$msg"
		esac
	done
	shift $(($OPTIND-1))
	file="$1"
	# Test variable presence
	echo_text -fp -$CONST_level_verbose_function "Checking variable '${data}' ... "
	rrdtool fetch "${CONFIG_rrd_file}" AVERAGE --start end+0 | head -1 | grep ${data} >/dev/null
	if [ $? -eq 0 ]
	then
		echo_text -$CONST_level_verbose_function "valid. Proceeding."
	else
		echo_text -$CONST_level_verbose_function "invalid. Ignoring."
		return
	fi
	# Creating graph
	echo_text -f -$CONST_level_verbose_function "Creating RRD graph '${file}'$(dryrun_token)."
	rrdtool graph "${file}" \
	--start ${time} \
	--imgformat PNG \
	--title "${title}" \
	--vertical-label "${label} (${unit})" \
	--alt-autoscale \
	--alt-y-grid \
	DEF:${data}="${CONFIG_rrd_file}":${data}:AVERAGE \
	CDEF:${vname}=${data},1000,/ \
	LINE${width}:${vname}\#${color}:"${label}\c" \
	GPRINT:${vname}:MIN:"Min\: %3.1lf${unit}" \
	GPRINT:${vname}:LAST:"%3.1lf${unit}" \
	GPRINT:${vname}:MAX:"Max\: %3.1lf${unit}" \
	> /dev/null
}
# <- END _functions

# Process command line parameters
process_options $@
while getopts "${LIB_options}O:G:" opt
do
	case "$opt" in
	O)
		CONFIG_graph_owner=$OPTARG
		;;
	G)
		CONFIG_graph_group=$OPTARG
		;;
	\?)
		msg="Unknown option '-$OPTARG'."
		fatal_error "$msg $help"
		;;
	:)
		case "$OPTARG" in
		O)
			msg="Missing owner for option '-$OPTARG'."
			;;
		G)
			msg="Missing group for option '-$OPTARG'."
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
# RRD file
if [ -n "$1" ]
then
	CONFIG_rrd_file="$1"
fi
# Graph folder
if [ -n "$2" ]
then
	CONFIG_graph_dir="$2"
fi
init_script

# Set default graph dir
if [ -z "$CONFIG_graph_dir" ]
then
	CONFIG_graph_dir="$(dirname "${CONFIG_rrd_file}")"
fi

process_folder -t "Status" -f "${CONFIG_status}"
process_folder -t "RRD" -fex "${CONFIG_rrd_file}"
process_folder -t "Graph" -ce "${CONFIG_graph_dir}"
show_configs

# -> Script execution
trap stop_script EXIT
if [ -n "$CONFIG_status" ]
then
	msg="Generating graphs in '${CONFIG_graph_dir}' from '${CONFIG_rrd_file}'."
	echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status' ... $msg"
	echo_text -ISL -$CONST_level_verbose_none "$msg" > "$CONFIG_status"
fi

# Set graph file base
if [ $CONFIG_flag_dryrun -eq 1 ]
then
	CONFIG_graph_dir="/tmp/"
fi
GRAPH_file_root="$(basename "${CONFIG_rrd_file}")"
GRAPH_file_root="${CONFIG_graph_dir}"/"${GRAPH_file_root%\.*}"
GRAPH_file_root="$(echo "${GRAPH_file_root}" | tr -s '/')"

# Line graph with system temperature for last 24 hours
GRAPH_file="${GRAPH_file_root}_soc_24h.${CONFIG_graph_ext}"
create_graph_line_single \
	-t "SoC Temperature" \
	-d temp1 \
	-w 2 \
	"$GRAPH_file"

# Line graph with waterproof sensor temperature for last 24 hours
GRAPH_file="${GRAPH_file_root}_wp_24h.${CONFIG_graph_ext}"
create_graph_line_single \
	-t "Waterproof DS18B20 Temperature" \
	-d temp2 \
	-w 2 \
	"$GRAPH_file"

# Line graph with module sensor temperature for last 24 hours
GRAPH_file="${GRAPH_file_root}_module_24h.${CONFIG_graph_ext}"
create_graph_line_single \
	-t "DS18B20 Module Temperature" \
	-d temp3 \
	-w 2 \
	"$GRAPH_file"

# Change ownership of all graph files
if [ $CONFIG_flag_dryrun -eq 0 ]
then
	chown ${CONFIG_graph_owner}:${CONFIG_graph_group} "${GRAPH_file_root}"*."${CONFIG_graph_ext}"
fi
# End of script processed by TRAP
