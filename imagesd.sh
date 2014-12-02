#!/usr/bin/env bash
#
# NAME:
#   imagesd.sh - manually backup entire SD card to an image file
#
# SYNOPSIS:
#   imagesd.sh [OPTION [ARG]] [backup_folder]
#
# DESCRIPTION:
# Script makes a binary backup of the entire SD card to a backup location as an image file
# and displays progress of the backing up process if it is not suppressed.
# - Script has to be run under root privileges (sudo ...).
# - Script can be run manually or under cron.
# - In manual mode the progress bar is displayed.
# - From cron the script should be user in quiet mode.
# - Image file name is composed of current hostname and current datetime.
# - Image file is not compressed and can be mount as an external source directly.
# - Script stops declared services during the backup process.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing values
#   of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#   in a configuration file declared in the command line.
# - Script performes rotating backup, i.e., it deletes obsolete backup files older than
#   predefined number of days (default 15) before the current time of the backup process.
# - In simulation mode the script uses 'touch' instead of 'dd', so that it creates
#   an empty backup image file as well as it does not executes rotation backup files.
#
# Example of backup image file (the placeholder <hostname> will be replaced
# with real box hostname):
# 	<hostname>_2013-12-31_23h59m.img
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
#		0=none, 1=errors (default), 2=mails, 3=info, 4=functions, 5=full
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
#   -q
#       Quiet. Do not display progress bar during creating image file.
#   -R days
#       Rotation. Rewrites of default rotation days for obsolete backup image files.
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
CONFIG_version="2.3.0"
CONFIG_commands=('du') # Array of generally needed commands
CONFIG_commands_run=('sync' 'dd' 'blockdev' 'pv') # Array of commands for full running
CONFIG_commands_dryrun=('touch') # Array of commands for dry running
CONFIG_level_verbose=3	# Level of verbosity to console - 0=none, 1=error, 2=mail, 3=info, 4=function, 5=full
CONFIG_flag_root=1	# Check root privileges flag
#
CONFIG_backup_dir="/var/backups/images"	# Backup folder - should be symbolic link to a final backup folder
CONFIG_services=('apache2' 'nginx' 'mysql' 'cron') # Services to be temporarily stopped - intensively writing to a disk
CONFIG_rotation_days=15	# Number of days for keeping backup files in the backup folder
CONFIG_timestamp_format="%Y-%m-%d_%Hh%Mm"	# Date and time expression in timestamps
CONFIG_backup_file_prefix="$(hostname)_"	# Prefix of a backup file - root name
CONFIG_backup_file_suffix=".img"	# Suffix of a backup file - extension
#
CONFIG_sdhc="/dev/mmcblk0"	# The device to be backed up
CONFIG_block_size="2M"	# The block size for 'dd' in its syntax
CONFIG_base_dir=""	# Base folder supperordinate to backup folder
CONFIG_flag_quiet=0	# Quiet mode flag
# <- END _config

# -> BEGIN _functions

# @info:	Displays usage description
# @args:	none
# @return:	none
# @deps:	none
show_help () {
	echo
	echo "$(basename $0) [OPTION [ARG]] [backup_folder]"
	echo "
Backup SD card into image file and delete obsolete backup files
in default backup folder '${CONFIG_backup_dir}'.
$(process_help -o)
  -q			quiet: do not display progress bar during creating image file
  -R days		Rotation: performs rotation for backup image files older than days; default ${CONFIG_rotation_days}
$(process_help -f)
"
}

# @info:	Actions at finishing script invoked by 'trap'
# @args:	none
# @return:	none
# @deps:	none
stop_script () {
	start_services ${CONFIG_services[@]}
	show_manifest STOP
}

# @info:	Start services from input list
# @args:	List of services
# @return:	0 or list of started services
# @deps:	none
start_services () {
	echo_text -hp -$CONST_level_verbose_mail "Starting services$(dryrun_token) ..."
	local srv_list
	srv_list=''
	if [[ $CONFIG_flag_dryrun -eq 1 ]]
	then
		for service
		do
			srv_list+=" ${service}"
		done
		[[ ! ${srv_list} ]] && srv_list='<none>'
		echo_text -$CONST_level_verbose_mail "${srv_list} ... skipped."
		return 0
	fi
	for service
	do
		service ${service} start &>/dev/null
		if (( $? == 0 ))
		then
			srv_list+=" ${service}"
		fi
	done
	[[ ! ${srv_list} ]] && srv_list='<none>'
	echo_text -$CONST_level_verbose_mail "${srv_list}."
	log_text -$CONST_level_logging_info "Starting services '${srv_list}'."
}

# @info:	Stop services from input list
# @args:	list of services
# @return:	0 or list of stopped services
# @deps:	none
stop_services () {
	echo_text -hp -$CONST_level_verbose_mail "Stopping services$(dryrun_token) ..."
	local srv_list
	srv_list=''
	if (( $CONFIG_flag_dryrun ))
	then
		for service
		do
			srv_list+=" ${service}"
		done
		[[ ! ${srv_list} ]] && srv_list='<none>'
		echo_text -$CONST_level_verbose_mail "${srv_list} ... skipped."
		return 0
	fi
	for service
	do
		service ${service} stop &>/dev/null
		if (( $? == 0 ))
		then
			srv_list+=" ${service}"
		fi
	done
	[[ ! ${srv_list} ]] && srv_list='<none>'
	echo_text -$CONST_level_verbose_mail "${srv_list}."
	log_text -$CONST_level_logging_info "Stopping services '${srv_list}'."
}

# @info:	List obsolete backup files and perform input actions
# @args:	List of actions for find command
# @return:	List of obsolete files for empty args
# @deps:	none
rotate_backups () {
    local cmd_find
	cmd_find="find \"${CONFIG_backup_dir}/\" -maxdepth 1 -name \"${CONFIG_backup_file_prefix}*${CONFIG_backup_file_suffix}\" -mtime +${CONFIG_rotation_days} -type f"
	eval ${cmd_find}
	if (( $# > 0 ))
	then
		eval ${cmd_find} $@
	fi
}
# <- END _functions

# Process input arguments
process_options $@
while getopts "${LIB_options}qR:" opt
do
	case "$opt" in
	q)
		CONFIG_flag_quiet=1
		;;
	R)
		CONFIG_rotation_days="$OPTARG"
		;;
	\?)
		msg="Unknown option '-$OPTARG'."
		fatal_error "$msg $help"
		;;
	:)	
		case "$OPTARG" in
		R)
			msg="Missing number of rotation days for option '-$OPTARG'."
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
	CONFIG_backup_dir="$1"
fi

init_script
process_folder -t "Status" -f "${CONFIG_status}"
process_folder -t "Base" -f "${CONFIG_backup_dir}"
process_folder -t "Backup" -ce "${CONFIG_backup_dir}"
show_configs

# -> Script execution
trap stop_script EXIT
if [ -n "$CONFIG_status" ]
then
	echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status'."
	echo_text -ISL -$CONST_level_verbose_none "Backing up SD card image." > "$CONFIG_status"
fi
TIME_start=$(date +%s)
stop_services ${CONFIG_services[@]}
echo_text -h -$CONST_level_verbose_mail "Backup Start Time $(date +"%F %T")."
BACKUP_FILE="${CONFIG_backup_dir}/${CONFIG_backup_file_prefix}$(date +${CONFIG_timestamp_format})${CONFIG_backup_file_suffix}"
BACKUP_FILE="$(echo "${BACKUP_FILE}" | tr -s '/')"
log_text -$CONST_level_logging_info "Backup started to '${BACKUP_FILE}'."
echo_text -s -$CONST_level_verbose_mail "Creating image file '${BACKUP_FILE}'$(dryrun_token) ... Can take several minutes."
if [ $CONFIG_flag_dryrun -eq 1 ]
then
	touch ${BACKUP_FILE}
else
	sync; sync
	if [ $CONFIG_flag_quiet -eq 1 ]
	then
		dd if="${CONFIG_sdhc}" of="${BACKUP_FILE}" bs=${CONFIG_block_size}
	else
		SD_SIZE=$(blockdev --getsize64 ${CONFIG_sdhc})
		pv -tpreb ${CONFIG_sdhc} -s ${SD_SIZE} | dd of="${BACKUP_FILE}" bs=${CONFIG_block_size} conv=sync,noerror iflag=fullblock
	fi
fi
RESULT=$?
echo_text -sp -$CONST_level_verbose_mail "Backing up ... "
if [ $RESULT -eq 0 ]
then
	echo_text -$CONST_level_verbose_mail "succeded."
	log_text -$CONST_level_logging_info  "Backup to '${CONFIG_backup_dir}' finished."
    # Rotation - delete obsolete log file older then rotation days ago the current time
	echo_text -h -$CONST_level_verbose_mail "Rotating ${CONFIG_rotation_days} days backups$(dryrun_token):"
	if [ $CONFIG_flag_dryrun -eq 1 ]
	then
		FILE_LIST=$(rotate_backups)
	else
		FILE_LIST=$(rotate_backups -delete)
	fi
	if [ -n "$FILE_LIST" ]
	then
		echo_text -$CONST_level_verbose_mail "$FILE_LIST"
	else
		echo_text -s -$CONST_level_verbose_mail "N/A"
	fi
	log_text -$CONST_level_logging_info "Rotation in '${CONFIG_backup_dir}' finished."
else
	echo_text -$CONST_level_verbose_error "failed."
	echo_text -s -$CONST_level_verbose_error "Rotation in '${CONFIG_backup_dir}' not executed."
	log_text -$CONST_level_logging_error  "Backup to '${CONFIG_backup_dir}' failed."
	log_text -$CONST_level_logging_error  "Rotation in '${CONFIG_backup_dir}' not perfomed."
fi
echo_text -h -$CONST_level_verbose_mail "Backup Stop Time $(date +"%F %T")."
TIME_stop=$(date +%s)

# Backup duration
(( TIME_period = TIME_stop - TIME_start ))
TIME_process=$(seconds2time ${TIME_period})
msg="Backup duration ${TIME_process}."
echo_text -h -$CONST_level_verbose_mail "$msg"
log_text -$CONST_level_logging_info "$msg"
# <- Backup SD card

# Final information
if [ -d "${CONFIG_backup_dir}" ]
then
	SPACE_backup=$(du -hsH "${CONFIG_backup_dir}")
	echo_text -h -$CONST_level_verbose_mail "Total disk space used for backup storage ... %s" "${SPACE_backup}."
	log_text -$CONST_level_logging_info "Backup space used '%s'." "${SPACE_backup}."
fi

# End of script processed by TRAP
