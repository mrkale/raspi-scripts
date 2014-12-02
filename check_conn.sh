#!/usr/bin/env bash
#
# NAME:
#   check_conn.sh - Check status of a network connection to the router and internet
#
# SYNOPSIS:
#   check_conn.sh [OPTION [ARG]] [log_file]
#
# DESCRIPTION:
# Script checks if a network connection to the router as well as to the internet is active and working.
# It sends the status of connection to Google Analytics and logs it into the system log as well.
# - Script has to be run under root privileges (sudo ...).
# - Script is supposed to run under cron.
# - Script marks connection status in Google Analytics as an event.
# - Script logs connection status in "user.log".
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#   in a configuration file declared in the command line.
# - For security reasons the Google Analytics tracking and client ids should be written
#   only in configuration file. Putting them to a command line does not prevent them
#   to be revealed by cron in email messages as a subject.
# - In simulation mode the script does not send events to Google Analytics.
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
#   -T TID
#       Tracking. Google Analytics tracking id in format UA-XXXX-Y.
#   -C CID
#       Client. Google Analytics client id in format UUID v4.
#   -I
#       Internal: Check only internal connection to gateway.
#   -R ifc,restart_fails,reboot_fails
#       Recovery: Comma separated
#		- Interface to restart,
#		- Number of internal connection fails to restart interface,
#		- Number of internal connection fails to reboot system
#	e.g., wlan0,3,12. Negative or zero number supresses restarting
#	or rebooting altogether.
#   -1
#      Force internal. Pretend failed internal network connection.
#   -2
#      Force external. Pretend failed external network connection.
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
CONFIG_commands=('grep' 'awk' 'ip' 'ping') # Array of generally needed commands
CONFIG_commands_run=('curl' 'ifdown' 'ifup' 'reboot') # List of commands for full running
CONFIG_flag_root=1	# Check root privileges flag
#
CONFIG_pings=4	# Number of pings to test an interface
CONFIG_google_ip="213.151.210.24"	# External test IP address of Google, inc.
CONFIG_ga_req="http://www.google-analytics.com/collect"	# Google Analytics request
CONFIG_ga_tid="UA-XXXX-Y"	# Google Analytics track id - should be in an input argument
CONFIG_ga_cid="0"	# Google Analytics client id - UUID v4
CONFIG_ga_ec=$(hostname)	# Google Analytics event category - hostname
CONFIG_ga_ea="${CONFIG_script%\.*}"
CONFIG_ga_ea="${CONFIG_ga_ea^^*}"	# Google Analytics event action - root script's name
CONFIG_ga_el=""	# Google Analytics event label - result message
CONFIG_ga_ev=0	# Google Analytics event value - number of failures in a serie
CONFIG_flag_force_fail_int=0
CONFIG_flag_force_fail_ext=0
CONFIG_flag_check_only_int=0
CONFIG_ifc=eth0	# Interface to restart at connection lost
CONFIG_fails_restart=0	# Number of continues connection fails to restart interface
CONFIG_fails_reboot=0	# Number of continues connection fails to reboot system; min. for restart
CONFIG_log_file="$0.err"	# Error log file
# <- END _config

# -> BEGIN _functions

# @info:	Display usage description
# @args:	(none)
# @return:	(none)
# @deps:	(none)
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]] [log_file]"
	echo "
Check network connection to the router and internet
and write a result message to user.log and Google Analytics.
$(process_help -o)
  -T TID		Tracking: Google Analytics tracking id (UA-XXXX-Y)
  -C CID		Client: Google Analytics client id (UUID v4)
  -I			Internal: Check only internal connection
  -R ifc,restart_fails,reboot_fails
			Recovery: Comma separated
			Interface to restart,
			Number of internal connection fails to restart interface,
			Number of internal connection fails to reboot system
			e.g., wlan0,3,12. Negative or zero number supresses restarting
			or rebooting altogether.
  -1			pretend (force) failed internal connection
  -2			pretend (force) failed external connection
$(process_help -f)
"
}

# @info:	Send event to Google Analytics
# @args:	Configuration parameters
# @return:	(none)
# @deps:	(none)
ga_event () {
	echo_text -h -$CONST_level_verbose_function "Logging to Google Analytics$(dryrun_token) ... ${CONFIG_ga_el} ... ${CONFIG_ga_ev}"
	if [[ $CONFIG_flag_dryrun -eq 0 ]]
	then
		curl \
			--data-urlencode "v=1" \
			--data-urlencode "tid=${CONFIG_ga_tid}" \
			--data-urlencode "cid=${CONFIG_ga_cid}" \
			--data-urlencode "t=event" \
			--data-urlencode "ec=${CONFIG_ga_ec}" \
			--data-urlencode "ea=${CONFIG_ga_ea}" \
			--data-urlencode "el=${CONFIG_ga_el}" \
			--data-urlencode "ev=${CONFIG_ga_ev}" \
		"${CONFIG_ga_req}" >/dev/null 2>&1
	fi
}

# @info:	Intialize log variables
# @opts:	-I ... initialize log variables for internal connection
#			-E ... initialize log variables for external connection
#			-A ... initialize all log variables
# @return:	(none)
# @deps:	(none)
init_logvars () {
	local OPTIND opt
	while getopts ":IEA" opt
	do
		case "$opt" in
		I)
			LOG_int_fails=0
			LOG_int_msg=""
			LOG_int_fails_start=0
			LOG_int_fails_start_time=""
			LOG_int_fails_stop=0
			LOG_int_fails_stop_time=""
			LOG_int_fails_period=0
			LOG_int_fails_period_time=""
			LOG_ifc_restarts=0
			LOG_ifc_msg=""
			LOG_os_restarts=0
			LOG_os_msg=""
			;;
		E)
			LOG_ext_fails=0
			LOG_ext_msg=""
			LOG_ext_fails_start=0
			LOG_ext_fails_start_time=""
			LOG_ext_fails_stop=0
			LOG_ext_fails_stop_time=""
			LOG_ext_fails_period=0
			LOG_ext_fails_period_time=""
			;;
		A)
			LOG_time_init=$(date +"%F %T")
			${FUNCNAME[0]} -I
			${FUNCNAME[0]} -E
			;;
		esac
	done
}

# @info:	Save log variables to log file
# @args:	(none)
# @return:	(none)
# @deps:	LOG_* variables
save_logvars () {
	LOG_time_save=$(date +"%F %T")
	if [[ LOG_int_fails -gt 0 || LOG_ext_fails -gt 0 ]]
	then
		set | grep "^LOG_" > "${CONFIG_log_file}"
	elif [[ -f "${CONFIG_log_file}" ]]
	then
		rm "${CONFIG_log_file}"
	fi
}

# @info:	Actions at finishing script invoked by 'trap'
# @args:	none
# @return:	none
# @deps:	Overloaded library function
stop_script () {
	save_logvars
	show_manifest STOP
}
# <- END _functions

# Process command line parameters
process_options $@
while getopts "${LIB_options}T:C:IR:12" opt
do
	case "$opt" in
	T)
		CONFIG_ga_tid=$OPTARG
		;;
	C)
		CONFIG_ga_cid=$OPTARG
		;;
	I)
		CONFIG_flag_check_only_int=1
		;;
	R)
		# Parse list of arguments - interface, restart fails, reboot fails
		OrigIFS=$IFS
		IFS=","
		OPTARG=($OPTARG)
		CONFIG_ifc=${OPTARG[0]}
		CONFIG_fails_restart=${OPTARG[1]}
		CONFIG_fails_reboot=${OPTARG[2]}
		IFS=$OrigIFS
		;;
	1)
		CONFIG_flag_force_fail_int=1
		;;
	2)
		CONFIG_flag_force_fail_ext=1
		;;
	\?)
		msg="Unknown option '-$OPTARG'."
		fatal_error "$msg $help"
		;;
	:)
		case "$OPTARG" in
		T)
			msg="Missing Google Analytics track id for option '-$OPTARG'."
			;;
		C)
			msg="Missing Google Analytics client id for option '-$OPTARG'."
			;;
		R)
			msg="Missing recovery arguments for option '-$OPTARG'."
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
	CONFIG_log_file="$1"
fi

init_script
process_folder -t "Status" -f "${CONFIG_status}"
process_folder -t "Log" -cfe "${CONFIG_log_file}"
show_configs

# -> Script execution
trap stop_script EXIT

# Initialize all log variables
init_logvars -A

# Update log variables from log file
if [ -s "${CONFIG_log_file}" ]
then
	source "${CONFIG_log_file}"
fi

# Check active connection
message="Checking network connection"
if [ -n "$CONFIG_status" ]
then
	echo_text -s -$CONST_level_verbose_info "Writing to status file '$CONFIG_status'."
	echo_text -ISL -$CONST_level_verbose_none "$message." > "$CONFIG_status"
fi
echo_text -hp -$CONST_level_verbose_info "${message}$(dryrun_token) ... "
echo $(hostname -I | grep "^[[:digit:]{1,3}\.{3}]") >/dev/null
RESULT=$?
if [[ $RESULT -eq 0 || $CONFIG_flag_dryrun -eq 1 ]]
then
	echo_text -$CONST_level_verbose_info "active. Proceeding."
else
	echo_text -$CONST_level_verbose_info "not active. Exiting."
	init_logvars -A
	exit
fi

# Check connection to gateway
TestIP="$(ip route | awk '/default/ { print $3 }')"
echo_text -h -$CONST_level_verbose_info "Checking internal connection ... '${TestIP}'."
if [ $CONFIG_flag_force_fail_int -eq 1 ]
then
	RESULT_INT=1
elif [ -n "$TestIP" ]
then
	ping -c${CONFIG_pings} ${TestIP} >/dev/null
	RESULT_INT=$?
else
	RESULT_INT=2
fi

# Internal connection status
if [ $RESULT_INT -eq 0 ]
then
	CONFIG_ga_ev=0
	CONFIG_ga_el="Internal network connection active"
	echo_text -s -$CONST_level_verbose_info "${CONFIG_ga_el}. Proceeding."
	log_text -$CONST_level_logging_info "${CONFIG_ga_el}"
	if [ $LOG_int_fails -gt 0 ]
	then
		LOG_int_fails_stop=$(date +%s)
		LOG_int_fails_stop_time=$(date +"%F %T")
		(( LOG_int_fails_period = LOG_int_fails_stop - LOG_int_fails_start ))
		LOG_int_fails_period_time=$(seconds2time ${LOG_int_fails_period})
	fi
else
	if [ $LOG_int_fails -eq 0 ]
	then
		LOG_int_fails_start=$(date +%s)
		LOG_int_fails_start_time=$(date +"%F %T")
	fi
	(( LOG_int_fails++ ))
	LOG_int_msg="Internal network connection failed"
	echo_text -s -$CONST_level_verbose_info "${LOG_int_msg} ... ${LOG_int_fails}x. Exiting."
	log_text -$CONST_level_logging_error "${LOG_int_msg} ... ${LOG_int_fails}x"
	# Restart system after every defined number of connection fails
	if [[ $CONFIG_fails_reboot -gt 0 && $(( $LOG_int_fails % $CONFIG_fails_reboot )) -eq 0 ]]
	then
		(( LOG_os_restarts++ ))
		LOG_os_msg="System rebooted"
		echo_text -s -$CONST_level_verbose_info "${LOG_os_msg} ... ${LOG_os_restarts}x. Rebooting."
		log_text -$CONST_level_logging_error "${LOG_os_msg} ... ${LOG_os_restarts}x"
		if [[ $CONFIG_flag_dryrun -eq 0 ]]
		then
			reboot
		fi
		exit
	fi
	# Restart interface after every defined number of connection fails
	if [[ $CONFIG_fails_restart -gt 0 && $(( $LOG_int_fails % $CONFIG_fails_restart )) -eq 0 ]]
	then
		(( LOG_ifc_restarts++ ))
		LOG_ifc_msg="Interface ${CONFIG_ifc} restarted"
		echo_text -s -$CONST_level_verbose_info "${LOG_ifc_msg} ... ${LOG_ifc_restarts}x. Exiting."
		log_text -$CONST_level_logging_error "${LOG_ifc_msg} ... ${LOG_ifc_restarts}x"
		if [[ $CONFIG_flag_dryrun -eq 0 ]]
		then
			ifdown --force ${CONFIG_ifc}
			ifup --force ${CONFIG_ifc}
		fi
	fi
	exit
fi
if [ $CONFIG_flag_check_only_int -eq 1 ]
then
	exit
fi

# Check connection to internet
TestIP=${CONFIG_google_ip}
echo_text -h -$CONST_level_verbose_info "Checking external connection ... '${TestIP}'."
if [ $CONFIG_flag_force_fail_ext -eq 1 ]
then
	RESULT_EXT=1
elif [ -n "$TestIP" ]
then
	ping -c${CONFIG_pings} ${TestIP} >/dev/null
	RESULT_EXT=$?
else
	RESULT_EXT=2
fi

# External connection status
if [ $RESULT_EXT -eq 0 ]
then
	CONFIG_ga_ev=0
	CONFIG_ga_el="External network connection active"
	echo_text -s -$CONST_level_verbose_info "${CONFIG_ga_el}. Proceeding."
	log_text -$CONST_level_logging_info "${CONFIG_ga_el}"
	ga_event
	if [ $LOG_ext_fails -gt 0 ]
	then
		LOG_ext_fails_stop=$(date +%s)
		LOG_ext_fails_stop_time=$(date +"%F %T")
		(( LOG_ext_fails_period = LOG_ext_fails_stop - LOG_ext_fails_start ))
		LOG_ext_fails_period_time=$(seconds2time ${LOG_ext_fails_period})
	fi
	# Log previous internal failures to Google Analytics
	if [ $LOG_int_fails -gt 0 ]
	then
		CONFIG_ga_ev=$LOG_int_fails
		CONFIG_ga_el=$LOG_int_msg
		ga_event
		echo_text -h -$CONST_level_verbose_mail "${LOG_int_msg} ... ${LOG_int_fails}x before."
		echo_text -s -$CONST_level_verbose_mail "For ${LOG_int_fails_period_time} ... from ${LOG_int_fails_start_time} to ${LOG_int_fails_stop_time}."
		log_text -$CONST_level_logging_error "${LOG_int_msg} ... ${LOG_int_fails}x before ... for ${LOG_int_fails_period_time} ... from ${LOG_int_fails_start_time} to ${LOG_int_fails_stop_time}."
		# Log interface restarts
		if [ $LOG_ifc_restarts -gt 0 ]
		then
			CONFIG_ga_ev=$LOG_ifc_restarts
			CONFIG_ga_el=$LOG_ifc_msg
			ga_event
			echo_text -h -$CONST_level_verbose_mail "${LOG_ifc_msg} ... ${LOG_ifc_restarts}x before."
			log_text -$CONST_level_logging_error "${LOG_ifc_msg} ... ${LOG_ifc_restarts}x before."
		fi
		# Log system reboots
		if [ $LOG_os_restarts -gt 0 ]
		then
			CONFIG_ga_ev=$LOG_os_restarts
			CONFIG_ga_el=$LOG_os_msg
			ga_event
			echo_text -h -$CONST_level_verbose_mail "${LOG_os_msg} ... ${LOG_os_restarts}x before."
			log_text -$CONST_level_logging_error "${LOG_os_msg} ... ${LOG_os_restarts}x before."
		fi
		echo_text -h -$CONST_level_verbose_mail "Logged to Google Analytics."
		echo_text -$CONST_level_verbose_mail
		init_logvars -I
	fi
	# Log previous external failures to Google Analytics
	if [ $LOG_ext_fails -gt 0 ]
	then
		CONFIG_ga_ev=$LOG_ext_fails
		CONFIG_ga_el=$LOG_ext_msg
		ga_event
		echo_text -h -$CONST_level_verbose_mail "${LOG_ext_msg} ... ${LOG_ext_fails}x before."
		echo_text -s -$CONST_level_verbose_mail "For ${LOG_ext_fails_period_time} ... from ${LOG_ext_fails_start_time} to ${LOG_ext_fails_stop_time}."
		echo_text -s -$CONST_level_verbose_mail "Logged to Google Analytics."
		echo_text -s -$CONST_level_verbose_mail
		log_text -$CONST_level_logging_error "${LOG_ext_msg} ... ${LOG_ext_fails}x before ... for ${LOG_ext_fails_period_time} ... from ${LOG_ext_fails_start_time} to ${LOG_ext_fails_stop_time}."
		init_logvars -E
	fi
else
	if [ $LOG_ext_fails -eq 0 ]
	then
		LOG_ext_fails_start=$(date +%s)
		LOG_ext_fails_start_time=$(date +"%F %T")
	fi
	(( LOG_ext_fails++ ))
	LOG_ext_msg="External network connection failed"
	echo_text -s -$CONST_level_verbose_info "${LOG_ext_msg} ... ${LOG_ext_fails}x. Exiting."
	log_text -$CONST_level_logging_error "${LOG_ext_msg} ... ${LOG_ext_fails}x"
fi

# End of script processed by TRAP
