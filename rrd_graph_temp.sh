#!/usr/bin/env bash
#
# NAME:
#   rrd_graph_temp.sh - Generating temperature graphs from RRD
#
# SYNOPSIS:
#   rrd_graph_temp.sh [OPTION [ARG]] RRD_file [Graph_dir]
#
# DESCRIPTION:
# Script generates graphs from Round Robin Database and puts them into web server documents folder.
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
# - In simulation mode the script generates graph files to folder '/tmp'.
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
CONFIG_version="0.4.0"
CONFIG_commands=('rrdtool' 'chown' 'awk' 'md5sum') # List of commands for full running
#
CONFIG_rrd_file="${CONFIG_script%\.*}.rrd"	# Round Robin Database file
CONFIG_graph_dir_target=""	# Target folder for storing graph pictures
CONFIG_graph_dir_defs=""	# Folder with graph definition files
CONFIG_graph_ext_pic="png"	# Graph picture file extension
CONFIG_graph_ext_def="gdf"	# Graph definition file extension
CONFIG_graph_ext_dsc="txt"	# Graph description file extension
CONFIG_graph_owner="www-data"	# Graph picture file owner to set after generation
CONFIG_graph_group="www-data"	# Graph picture file group to set after generation
# <- END _config

# -> BEGIN _graph definitions
# Placeholder for variables read from definition files and put to graph creation function
GRAPH_tag=""
GRAPH_file_root=""
# From definition file
GRAPH_title=""
GRAPH_desc=""
GRAPH_data=""
GRAPH_fnc=""
GRAPH_label=""
GRAPH_color=""
GRAPH_width=""
GRAPH_start=""
# -> END _graph definitions

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
# @opts:	-t title    ... name of a graph prefixed with hostname in uppercase (default none)
#			-d data     ... name of the DS variable in RRD
#			-f function ... RRD cumulative function (default "AVERAGE")
#			-l label    ... descriptive name of the DS variable (default "Temperature")
#			-c color    ... color of the line in pattern RRGGBB (default "FF0000")
#			-w width    ... width of the line in pixels (default 1)
#			-s start     ... start AT-STYLE time expression (default "-1d")
# @args:	none
# @return:	none
# @deps:	none
create_graph_line_single () {
	local file data vname
	local function="AVERAGE"
	local system="$(hostname)" unit="°C" time="-1d" width="1"
	local title="${system^^*}" label="Temperature" color="FF0000"
	local OPTIND opt
	# Process input parameters
	while getopts ":t:d:f:l:c:s:w:" opt
	do
		case "$opt" in
		t)
			title+=" - $OPTARG"
			;;
		d)
			data="$OPTARG"
			vname="${data}_01"
			;;
		f)
			function="$OPTARG"
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
	rrdtool fetch "${CONFIG_rrd_file}" ${function} --start end+0 | head -1 | grep ${data} >/dev/null
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
	DEF:${data}="${CONFIG_rrd_file}":${data}:${function} \
	CDEF:${vname}=${data},1000,/ \
	LINE${width}:${vname}\#${color}:"${label}\c" \
	GPRINT:${vname}:MIN:"Min\: %3.1lf${unit}" \
	GPRINT:${vname}:LAST:"%3.1lf${unit}" \
	GPRINT:${vname}:MAX:"Max\: %3.1lf${unit}" \
	> /dev/null
}

# @info:	Intialize graph definition variables
# @opts:	-I ... initialize variables
#			-E ... erase variables
# @return:	(none)
# @deps:	(none)
init_graphvars () {
	local OPTIND opt
	while getopts ":IE" opt
	do
		case "$opt" in
		I)
			GRAPH_title="Temperature Graph"
			GRAPH_desc=""
			GRAPH_data="temp1"
			GRAPH_fnc="AVERAGE"
			GRAPH_label="Temperature"
			GRAPH_color="FF0000"
			GRAPH_width=1
			GRAPH_start="-1d"
			;;
		E)
			GRAPH_title=""
			GRAPH_desc=""
			GRAPH_data=""
			GRAPH_fnc=""
			GRAPH_label=""
			GRAPH_color=""
			GRAPH_width=0
			GRAPH_start=""
			;;
		esac
	done
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
	CONFIG_graph_dir_target="$2"
fi
init_script

# Set default graph dir
if [ -z "$CONFIG_graph_dir_target" ]
then
	CONFIG_graph_dir_target="$(dirname "${CONFIG_rrd_file}")"
fi

process_folder -t "Status" -f "${CONFIG_status}"
process_folder -t "RRD" -fex "${CONFIG_rrd_file}"
process_folder -t "Graph" -ce "${CONFIG_graph_dir_target}"
process_folder -t "Definitions" -ex "${CONFIG_graph_dir_defs}"
show_configs

# -> Script execution
trap stop_script EXIT
if [ -n "$CONFIG_status" ]
then
	msg="Generated graphs in '${CONFIG_graph_dir_target}' from '${CONFIG_rrd_file}'."
	echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status'."
	echo_text -ISL -$CONST_level_verbose_none "$msg" > "$CONFIG_status"
fi

echo_text -h -$CONST_level_verbose_info "Generating graph files to '${CONFIG_graph_dir_target}' from '${CONFIG_rrd_file}':"
# Set graph file base
if [ $CONFIG_flag_dryrun -eq 1 ]
then
	CONFIG_graph_dir_target="/tmp/"
fi
GRAPH_file_root="$(basename "${CONFIG_rrd_file}")"
GRAPH_file_root="${CONFIG_graph_dir_target}"/"${GRAPH_file_root%\.*}"
GRAPH_file_root="$(echo "${GRAPH_file_root}" | tr -s '/')"

# Read definitions folder
for file in $(ls ${CONFIG_graph_dir_defs}/*.${CONFIG_graph_ext_def} 2>/dev/null)
do
	# Read graph parameters
	init_graphvars -I
	source "$file"
	GRAPH_tag=$(basename $file ".${CONFIG_graph_ext_def}")
	# Create graph picture file
	GRAPH_file="${GRAPH_file_root}_${GRAPH_tag}.${CONFIG_graph_ext_pic}"
	echo_text -s -$CONST_level_verbose_info "${GRAPH_file}"
	create_graph_line_single \
		-t "${GRAPH_title}" \
		-d "${GRAPH_data}" \
		-f "${GRAPH_fnc}" \
		-l "${GRAPH_label}" \
		-c "${GRAPH_color}" \
		-w "${GRAPH_width}" \
		-s "${GRAPH_start}" \
	"${GRAPH_file}"
	# Create graph description file
	if [ -n "${GRAPH_desc}" ]
	then
		GRAPH_file+=".${CONFIG_graph_ext_dsc}"
		# Chech if there is a new description
		if [[ ! -f "${GRAPH_file}" \
		|| "$(echo "${GRAPH_desc}" | md5sum | awk '1 {print $1}')" \
		!= "$( md5sum "${GRAPH_file}" | awk '1 {print $1}')" ]]
		then
			echo "${GRAPH_desc}" > "${GRAPH_file}"
			echo_text -s -$CONST_level_verbose_info "${GRAPH_file}"
		fi
	fi
done

# Change ownership of all graph files
if [ $CONFIG_flag_dryrun -eq 0 ]
then
	chown ${CONFIG_graph_owner}:${CONFIG_graph_group} "${GRAPH_file_root}"*."${CONFIG_graph_ext_pic}"
	chown ${CONFIG_graph_owner}:${CONFIG_graph_group} "${GRAPH_file_root}"*."${CONFIG_graph_ext_pic}.${CONFIG_graph_ext_dsc}"
fi
# End of script processed by TRAP
