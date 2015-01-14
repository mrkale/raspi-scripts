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
CONFIG_version="0.4.3"
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

# -> BEGIN _functions

# @info:	Display usage description
# @args:	none
# @return:	none
# @deps:	none
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]] RRD_file [output_dir]"
	echo "
Generate PNG temperature graphs from Round Robin Database.
Default output folder with graph pictures is folder containing the RRD.
$(process_help -o)
  -g graphs_dir		graphing: folder with graph definition files
  -O owner		Owner: owner of the graph files to set (default '$CONFIG_graph_owner')
  -G group		Group: group of the graph files to set (default '$CONFIG_graph_group')
$(process_help -f)
"
}

# @info:	Create RRD graph
# @opts:	none
# @args:	none
# @return:	none
# @deps:	none
create_graph_line () {
	local system="$(hostname)"
	local title="${system^^*}"
	local graph_cmd vname
	local last_fnc last_label last_unit last_color last_width

	# Casting graph parameters lists to arrays
	GRAPH_start=( $GRAPH_start )
	GRAPH_data=( $GRAPH_data )
	GRAPH_fnc=( $GRAPH_fnc )
	GRAPH_label=( $GRAPH_label )
	GRAPH_unit=( $GRAPH_unit )
	GRAPH_color=( $GRAPH_color )
	GRAPH_width=( $GRAPH_width )
	# Creating graph command
	echo_text -f -$CONST_level_verbose_function "Creating RRD graph '${GRAPH_file}'$(dryrun_token)."
	graph_cmd="rrdtool graph ${GRAPH_file}"
	graph_cmd+=" --start=${GRAPH_start}"
	graph_cmd+=" --imgformat=PNG"
	graph_cmd+=" --title=\"$title - ${GRAPH_title}\""
	graph_cmd+=" --vertical-label=\"${GRAPH_axisy}\""
	graph_cmd+=" --alt-autoscale"
	graph_cmd+=" --alt-y-grid"
	# graph_cmd+=" --slope-mode"
	# Process graphs variables
	for (( i=0; i < ${#GRAPH_data[@]}; i++ ))
	do
		# Synchronize graph parameters arrays with data array
		vname=${GRAPH_data[$i]}_01
		last_fnc=${GRAPH_fnc[$i]:-$last_fnc}
		last_label=${GRAPH_label[$i]:-$last_label}
		last_unit=${GRAPH_unit[$i]:-$last_unit}
		last_color=${GRAPH_color[$i]:-$last_color}
		last_width=${GRAPH_width[$i]:-$last_width}
		# Check variable presence in RRD
		echo_text -fp -$CONST_level_verbose_function "Checking variable '${GRAPH_data[$i]}' ... "
		rrdtool fetch "${CONFIG_rrd_file}" ${last_fnc} --start end+0 | head -1 | grep -w ${GRAPH_data[$i]} >/dev/null
		if [ $? -eq 0 ]
		then
			echo_text -$CONST_level_verbose_function "valid. Proceeding."
		else
			echo_text -$CONST_level_verbose_function "invalid. Ignoring."
			continue
		fi
		# Create data clauses
		graph_cmd+=" DEF:${GRAPH_data[$i]}=${CONFIG_rrd_file}:${GRAPH_data[$i]}:${last_fnc}"
		graph_cmd+=" CDEF:${vname}=${GRAPH_data[$i]},1000,/"
		graph_cmd+=" LINE${last_width}:${vname}#${last_color}:\"${last_label}\c\""
		graph_cmd+=" GPRINT:${vname}:MIN:\"Min\: %3.1lf${last_unit}\""
		graph_cmd+=" GPRINT:${vname}:LAST:\"%3.1lf${last_unit}\""
		graph_cmd+=" GPRINT:${vname}:MAX:\"Max\: %3.1lf${last_unit}\j\""
	done
	# echo_text -f -$CONST_level_verbose_function "$graph_cmd"
	eval ${graph_cmd} >/dev/null
}

# @info:	Setup of default graph definition variables
# @opts:	none
# @return:	none
# @deps:	none
default_graphvars () {
	GRAPH_title="Temperature Graph"
	GRAPH_axisy="Measurement"
	GRAPH_desc=""
	GRAPH_start="-1d"
	GRAPH_data="temp1"
	GRAPH_fnc="AVERAGE"
	GRAPH_label="Temperature"
	GRAPH_unit="°C"
	GRAPH_color="FF0000"
	GRAPH_width="1"
}

# <- END _functions

# Process command line parameters
process_options $@
while getopts "${LIB_options}g:O:G:" opt
do
	case "$opt" in
	g)
		CONFIG_graph_dir_defs="$OPTARG"
		;;
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
process_folder -t "Output" -ce "${CONFIG_graph_dir_target}"
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
	# Set default graph parameters
	default_graphvars
	# Read graph parameters
	source "$file"
	GRAPH_tag=$(basename $file ".${CONFIG_graph_ext_def}")
	# Create graph picture file
	GRAPH_file="${GRAPH_file_root}_${GRAPH_tag}.${CONFIG_graph_ext_pic}"
	echo_text -s -$CONST_level_verbose_info "${GRAPH_file}"
	create_graph_line "${GRAPH_file}"
	# Create graph description file
	if [ -n "${GRAPH_desc}" ]
	then
		GRAPH_file+=".${CONFIG_graph_ext_dsc}"
		# Check if there is a new description
		if [[ ! -f "${GRAPH_file}" \
		|| "$(echo "${GRAPH_desc}" | md5sum | awk '1 {print $1}')" \
		!= "$( md5sum "${GRAPH_file}" | awk '1 {print $1}')" ]]
		then
			echo "${GRAPH_desc}" > "${GRAPH_file}"
			echo_text -s -$CONST_level_verbose_info "${GRAPH_file}"
		fi
	fi
done

# Change ownership of all graph and description files
if [ $CONFIG_flag_dryrun -eq 0 ]
then
	filemasks=(	"${GRAPH_file_root}*.${CONFIG_graph_ext_pic}" \
				"${GRAPH_file_root}*.${CONFIG_graph_ext_pic}.${CONFIG_graph_ext_dsc}" \
			)
	for mask in "${filemasks[@]}"
	do
		if ls $mask 1>/dev/null 2>&1
		then
			chown ${CONFIG_graph_owner}:${CONFIG_graph_group} $mask 2>/dev/null
		fi
	done
fi
# End of script processed by TRAP
