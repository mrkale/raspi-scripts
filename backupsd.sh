#!/usr/bin/env bash
#
# NAME:
#   backupsd.sh - backup files on SD card to backup folder
#
# SYNOPSIS:
#   backupsd.sh [OPTION [ARG]] [backup_folder]
#
# DESCRIPTION:
# Script makes a files and folders backup of the root file system of SD card
# to a backup folder with help of utility 'rsync'.
# - Script has to be run under root privileges (sudo ...).
# - Script can be run manually or under cron.
# - The first backup to particular backup folder takes longer (couple of minutes), while
#   subsequent backups are just differential and may take much less time.
# - Some folders from file system have to be excluded from backup (virtual and system ones)
#   by writing them to the exclusion file declared in command line as a argument of
#   corresponding command line option. The exclusion file line for particular folder
#   should be in the form: /folder/*. It ensures that in the backup folder that folder
#   is created, but as empty.
# - Log file name is composed of current hostname, current script name,
#   and current datetime.
# - Log file is located by default to the base (superordinate) folder of the backup folder,
#   so that it does not mess the original content of the file system. However, the folder
#   of the log file can be declared in command line or a configuration file.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing
#   values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#	in a configuration file declared in the command line. The configuration file is read in
#	as a shell script so you can abuse that fact if you so want to.
# - Configuration file should contain only those configurtion parameters that you want to override.
# - Script performes rotating backup of log files, i.e., it deletes obsolete
#   log files older than predefined number of days (default 30) before
#   the current time of the backup process.
#   This number can be redefined by corresponding command line option.
# - In simulation mode the script does not backs up anything, just creates a log file.
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
#   -E ExclusionFile
#       Exclusion. File with list of excluded files and folders from backup.
#   -L LogFolder
#       Logger. Log folder defaulted to base folder of the backup folder.
#   -R days
#       Rotation. Rewrites of default rotation days for obsolete log files.
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
CONFIG_version="0.6.0"
CONFIG_commands=('du' 'rsync' 'sync') # Array of generally needed commands
CONFIG_flag_root=1	# Check root privileges flag
#
CONFIG_timestamp_format="%Y-%m-%d_%Hh%Mm"	# Date and time expression in timestamps
CONFIG_backup_dir=""	# Backup folder
CONFIG_log_prefix="$(hostname)_${CONFIG_script}_"	# Prefix of a log file - general name
CONFIG_log_suffix=".log"	# Suffix of a log file - extension
CONFIG_log_dir=""	# Log folder
CONFIG_exclude="${CONFIG_script}.exclude.lst"	# File with excluded files and folders from backup
CONFIG_rotation_days=30	# Number of days for keeping log files in the base folder
CONFIG_options_rsync='-avWE --delete-during --force'	# Options for utility 'rsync'
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
Backup root file system from SD card into a backup folder.
Boot partition in /boot is not excluded from backup by default.
If the backup folder is not declared in the command line,
it has to be declared in a configuration file.
$(process_help -o)
  -E exclusion_file	exclusion: file with list of excluded files from backup
  -L log_dir		Logger: logging folder defaulted to base folder of the backup folder
  -R days		Rotation: performs rotation for log files older than days; default ${CONFIG_rotation_days}
$(process_help -f)
"
}

# @info:	Fill exclusion file with default content
# @args:	none
# @return:	none
# @deps:	none
fill_exclusion_file () {
	echo_text -f -$CONST_level_verbose_function "Filling exclusion file '${CONFIG_exclude}' with default content."
	touch "${CONFIG_exclude}"
	echo "
/proc/*
/sys/*
/dev/*
/tmp/*
/run/*
/mnt/*
/media/*
/lost+found/*
/cygdrive/*
" > "${CONFIG_exclude}"
}

# @info:	List obsolete log files and perform input actions
# @args:	List of actions for find command
# @return:	List of obsolete files for empty args
# @deps:	none
rotate_logs () {
    local cmd_find
	cmd_find="find \"${CONFIG_log_dir}/\" -maxdepth 1 -name \"${CONFIG_log_prefix}*${CONFIG_log_suffix}\" -mtime +${CONFIG_rotation_days} -type f"
	eval ${cmd_find}
	if [[ $# -gt 0 ]]
	then
		eval ${cmd_find} $@
	fi
}
# <- END _functions

# Process input arguments
process_options $@
while getopts "${LIB_options}E:L:R:" opt
do
	case "$opt" in
	E)
		CONFIG_exclude=$OPTARG
		;;
	L)
		CONFIG_log_dir=$OPTARG
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
		E)
			msg="Missing exclusion file for option '-$OPTARG'."
			;;
		L)
			msg="Missing log folder for option '-$OPTARG'."
			;;
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

# Set log dir
if [ -z "$CONFIG_log_dir" ]
then
	CONFIG_log_dir="$(dirname "${CONFIG_backup_dir}")"
fi

# Process exclusion file
if [ -n "$CONFIG_exclude" ]
then
	echo_text -hp -$CONST_level_verbose_info "Checking exclusion file '$CONFIG_exclude' ... "
	if [ -f "$CONFIG_exclude" ]
	then
		if [ -s "$CONFIG_exclude" ]
		then
			echo_text -$CONST_level_verbose_info "exists and is not empty. Applying."
		else
			echo_text -$CONST_level_verbose_info "is empty. Adding default content."
			fill_exclusion_file
		fi
	else
		echo_text -$CONST_level_verbose_info "does not exist. Creating with default content."
		fill_exclusion_file
	fi
fi

# Check folders
process_folder -t "Status" -f "${CONFIG_status}"
process_folder -t "Base" -f "${CONFIG_backup_dir}"
process_folder -t "Backup" -ce "${CONFIG_backup_dir}"
process_folder -t "Log" -ce "${CONFIG_log_dir}"
show_configs

# -> Script execution
trap stop_script EXIT
if [ -n "$CONFIG_status" ]
then
	echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status'."
	echo_text -ISL -$CONST_level_verbose_none "Backing up SD card." > "$CONFIG_status"
fi
TIME_start=$(date +%s)
echo_text -h -$CONST_level_verbose_mail "Backup Start Time $(date +"%F %T")."
log_text -$CONST_level_logging_info "Backup started to '${CONFIG_backup_dir}'."
echo_text -s -$CONST_level_verbose_mail "Creating backup to folder '${CONFIG_backup_dir}'$(dryrun_token) ... Can take several minutes."
LOG_FILE="${CONFIG_log_dir}/${CONFIG_log_prefix}$(date +${CONFIG_timestamp_format})${CONFIG_log_suffix}"
CONFIG_options_rsync+=" --exclude-from="${CONFIG_exclude}""
sync; sync
rsync ${CONFIG_options_rsync} / "${CONFIG_backup_dir}/" > "${LOG_FILE}"
RESULT=$?
echo_text -sp -$CONST_level_verbose_mail "Backing up ... "
if [ $RESULT -eq 0 ]
then
	echo_text -$CONST_level_verbose_mail "succeded."
	log_text -$CONST_level_logging_info  "Backup to '${CONFIG_backup_dir}' finished."
    # Rotation - delete obsolete log file older then rotation days ago the current time
	echo_text -h -$CONST_level_verbose_mail "Rotating ${CONFIG_rotation_days} days logs$(dryrun_token):"
	if [ $CONFIG_flag_dryrun -eq 1 ]
	then
		FILE_LIST=$(rotate_logs)
	else
		FILE_LIST=$(rotate_logs -delete)
	fi
	if [ -n "$FILE_LIST" ]
	then
		echo_text -$CONST_level_verbose_mail "$FILE_LIST"
	else
		echo_text -s -$CONST_level_verbose_mail "N/A"
	fi
	log_text -$CONST_level_logging_info "Rotation in '${CONFIG_log_dir}' finished."
else
	echo_text -$CONST_level_verbose_error "failed."
	echo_text -s -$CONST_level_verbose_error "Rotation in '${CONFIG_backup_dir}' not executed."
	log_text -$CONST_level_logging_error  "Backup to '${CONFIG_backup_dir}' failed."
	log_text -$CONST_level_logging_error  "Rotation in '${CONFIG_backup_dir}' not perfomed."
fi
echo_text -h -$CONST_level_verbose_mail "Backup result log in file '${LOG_FILE}'."
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
