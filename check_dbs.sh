#!/usr/bin/env bash
#
# NAME:
#   check_dbs.sh - check tables in MySQL databases
#
# SYNOPSIS:
#   check_dbs.sh [OPTION [ARG]]
#
# DESCRIPTION:
# Script checks tables in selected MySQL databases.
# - Script is supposed to run under cron.
# - Script logs to "user.log".
# - Script may write its working status into a status (tick) file if defined, what may
#   be considered as a monitoring heartbeat of the script especially then in normal conditions
#   it produces no output.
# - Status file should be located in the temporary file system (e.g., in the folder /run)
#   in order to reduce writes to the SD card.
# - Script outputs corrupted tables into standard error output, if some have been detected.
# - Script checks only database tables under engines MyISAM, InnoDB, and Archive.
# - System databases are implicitly excluded from checking.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing
#   values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#	in a configuration file declared in the command line. The configuration file is read in
#	as a shell script so you can abuse that fact if you so want to.
# - Configuration file should contain only those configuration parameters
#   that you want to override.
#
# OPTIONS & ARGS:
#   -h
#       Help. Show usage description and exit.
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
#   -u User
#       User. Database user's name for accessing MySQL database server.
#   -p Password
#       Password. Database user's password for accessing MySQL database server.
#   -d Database
#       Database. Database to be checked. The option can be repeated for more databases.
#       Implicitly all databases except system ones are to be checked.
#   -1
#      Force corruption: Simulate the first table of every database as corrupted.
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
CONFIG_version="0.5.0"
CONFIG_commands=('grep' 'mysql' 'mysqlcheck') # Array of generally needed commands
#
CONFIG_db_excluded_dbs=('information_schema' 'performance_schema' 'mysql')	# Array of excluded databases from checking
CONFIG_db_included_dbs=()	# Array of included databases from checking
CONFIG_db_user=""	# Database user; should be just in configuration file
CONFIG_db_password=""	# User's db password; should be just in configuration file
CONFIG_flag_force_corruption=0	# Force (simulate) corrupted tables
# <- END _config

# -> BEGIN _functions

# @info:	Displays usage description
# @args:	none
# @return:	none
# @deps:	none
show_help () {
	echo
	echo "$(basename $0) [OPTION [ARG]]"
	echo "
Check MySQL database tables of all databases except system ones.
$(process_help -o)
  -u user		user: name of the database user
  -p password		password: password of the database user
  -d database		database: included database; option can be repeated for db list
  -1			Force corruption: Simulate the first table of every database as corrupted.
$(process_help -f)
"
}
# <- END _functions

# Process command line parameters
process_options $@
while getopts "${LIB_options}u:p:d:1" opt
do
	case "$opt" in
	u)
		CONFIG_db_user="$OPTARG"
		;;
	p)
		CONFIG_db_password="$OPTARG"
		;;
	d)
		CONFIG_db_included_dbs+=($OPTARG)
		;;
	1)
		CONFIG_flag_force_corruption=1
		;;
	\?)
		msg="Unknown option '-$OPTARG'."
		fatal_error "$msg $help"
		;;
	:)
		case "$OPTARG" in
		u)
			msg="Missing database user for option '-$OPTARG'."
			;;
		p)
			msg="Missing database password for option '-$OPTARG'."
			;;
		d)
			msg="Missing database for option '-$OPTARG'."
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
process_folder -t "Status" -f "${CONFIG_status}"
show_configs

# -> Script execution
trap stop_script EXIT
if [ -n "$CONFIG_status" ]
then
	echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status'."
	echo_text -ISL -$CONST_level_verbose_none "Checking databases." > "$CONFIG_status"
fi

# Log checking start
TIME_start=$(date +%s)
echo_text -h -$CONST_level_verbose_mail "Checking Start Time $(date +"%F %T")."
log_text -$CONST_level_logging_info "Checking started."

# List of all databases
if [ ${#CONFIG_db_included_dbs[@]} -eq 0 ]
then
	LIST_databases=($(mysql --user="${CONFIG_db_user}" --password="${CONFIG_db_password}" -BNe "show databases;"))
else
	LIST_databases=(${CONFIG_db_included_dbs[@]})
fi

# Remove excluded databases
for db in ${CONFIG_db_excluded_dbs[@]}
do
	LIST_databases=(${LIST_databases[@]##$db})
done
echo_text -hp -$CONST_level_verbose_mail "Databases to check ..."
if [ ${#LIST_databases[@]} -eq 0 ]
then
	echo_text -$CONST_level_verbose_mail " <none>."
else
	echo_text -$CONST_level_verbose_mail "$(printf " %s" "${LIST_databases[@]}")."
fi

# Check database
LIST_db_errors=""
shopt -s extglob
for db in ${LIST_databases[@]}
do
	LIST_tables=($(echo "SELECT table_name FROM information_schema.tables WHERE table_schema='${db}' AND engine in ('myisam', 'innodb', 'archive');" | mysql --user="${CONFIG_db_user}" --password="${CONFIG_db_password}" -s))
	if [[ $CONFIG_flag_force_corruption -eq 1 ]]
	then
		# Simulate the first table corrupted
		LIST_tbl_errors=$(printf "\n%s.%s\nerror: Simulated corruption\n" ${db} ${LIST_tables[0]})
		LIST_tbl_errors=${LIST_tbl_errors##+([[:space:]])}	# Extended pattern
		LIST_db_errors+=$LIST_tbl_errors
	else
		# Check table
		for tbl in ${LIST_tables[@]}
		do
			LIST_tbl_errors=$(mysqlcheck --user="${CONFIG_db_user}" --password="${CONFIG_db_password}" -s ${db} ${tbl})
			LIST_tbl_errors=${LIST_tbl_errors##+([[:space:]])}	# Extended pattern
			LIST_db_errors+=$LIST_tbl_errors
		done
	fi
done
shopt -u extglob

# Display result
if [ -z "$LIST_db_errors" ]
then
	message="No corrupted tables detected"
	echo_text -b -$CONST_level_verbose_mail "$message."
	log_text -$CONST_level_logging_info "$message"
	if [ -n "$CONFIG_status" ]
	then
		echo_text -h -$CONST_level_verbose_info "Writing to status file '$CONFIG_status'."
		echo_text -ISL -$CONST_level_verbose_none "$message." > "$CONFIG_status"
	fi
else
	echo_text -eb -$CONST_level_verbose_error "Corrupted tables detected.\n$LIST_db_errors"
	log_text -ES -$CONST_level_logging_error "Corrupted tables -- $LIST_db_errors"
fi
echo_text -hb -$CONST_level_verbose_mail "Checking Stop Time $(date +"%F %T")."
TIME_stop=$(date +%s)

# Checking duration
(( TIME_period = TIME_stop - TIME_start ))
TIME_process=$(seconds2time ${TIME_period})
msg="Checking duration ${TIME_process}."
echo_text -h -$CONST_level_verbose_mail "$msg"
log_text -$CONST_level_logging_info "$msg"

# End of script processed by TRAP
