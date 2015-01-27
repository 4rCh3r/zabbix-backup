#!/bin/bash
# NAME
#     zabbix-mysql-backupconf.sh - Configuration Backup for Zabbix 2.0 w/MySQL
#
# SYNOPSIS
#     This is a MySQL configuration backup script for Zabbix 2.0, 2.2 or 2.4.
#     It does a full backup of all configuration tables, but only a schema
#     backup of large data tables.
#
#     The script is based on a script by Ricardo Santos
#     (http://zabbixzone.com/zabbix/backuping-only-the-zabbix-configuration/)
#
#     Credits for some suggestions concerning the original script to:
#      - Ricardo Santos
#      - Oleksiy Zagorskyi (zalex)
#      - Petr Jendrejovsky
#      - Jonathan Bayer
#      - Andreas Niedermann (dre-)
#
# HISTORY
#     0.7.1 (2015-01-27)
#         NEW: Parsing of commandline arguments implemented
# 
#     0.7.0 (2014-10-02)
#         ENH: Complete overhaul to make script work with lots of Zabbix versions
#
#     0.6.0 (2014-09-15)
#         REV: Updated the table list for use with zabbix v2.2.3
#
#     0.5.0 (2013-05-13)
#         NEW: Added table list comparison between database and script
#
#     0.4.0 (2012-03-02)
#         REV: Incorporated mysqldump options suggested by Jonathan Bayer
#
#     0.3.0 (2012-02-06)
#         ENH: Backup of Zabbix 1.9.x / 2.0.0, removed unnecessary use of
#              variables (DATEBIN etc) for commands that use to be in $PATH
#
#     0.2.0 (2011-11-05)
#
# AUTHOR
#     Jens Berthold (maxhq), 2015


#
# DEFAULT VALUES
#
# following will store the backup in a subdirectory of the current directory
DUMPDIR="$(dirname "$(realpath -s "$0")")"
DBHOST="127.0.0.1"
DBNAME="zabbix"
DBUSER="zabbix"
DBPASS=""

#
# SHOW HELP
#
if [ -z "$1" ]; then
	cat <<EOF
USAGE
	$(basename $0) [options]
	
OPTIONS
	 -h host      - hostname/IP of MySQL server (default: $DBHOST)
	 -d database  - Zabbix database name (default: $DBNAME)
	 -u user      - MySQL user to access Zabbix database (default: $DBUSER)
	 -p password  - MySQL user password (specify "-" for a prompt)
	 -o outputdir - output directory for the MySQL dump file
	                (default: $DUMPDIR) 

EXAMPLE
	$(basename $0) -h 1.2.3.4 -d zabbixdb -u zabbix -p test
	$(basename $0) -d zabbixdb -u zabbix -p - -o /tmp
EOF
	exit 1
fi	

#
# PARSE COMMAND LINE ARGUMENTS
#
while getopts ":h:d:u:p:o:" opt; do
  case $opt in
    h)  DBHOST="$OPTARG" ;;
    d)  DBNAME="$OPTARG" ;;
    u)  DBUSER="$OPTARG" ;;
    p)  DBPASS="$OPTARG" ;;
    o)  DUMPDIR="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument" >&2; exit 1 ;;
  esac
done

if [ "$DBPASS" = "" ]; then
	echo "No password given" >&2
	exit 1
fi

if [ "$DBPASS" = "-" ]; then
	read -s -p "Enter MySQL password for user '$DBUSER' (input will be hidden): " DBPASS
	echo ""
fi

#
# CONSTANTS
#
MYSQL_CONN="-h ${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBNAME}"
MYSQL_BATCH="mysql --batch --silent $MYSQL_CONN"

DUMPFILEBASE="zabbix_$(date +%Y%m%d-%H%M).sql"
DUMPFILE="${DUMPDIR}/${DUMPFILEBASE}"

#
# CONFIG DUMP
#
cat <<EOF
Configuration:
 - host:     $DBHOST ($DBHOSTNAME)
 - database: $DBNAME
 - user:     $DBUSER
EOF

#
# FUNCTIONS
#

# Returns TRUE if argument 1 is part of the given array (remaining arguments)
elementIn () {
	local e
	for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
	return 1
}

#
# CHECKS
#
if [ ! -x /usr/bin/mysqldump ]; then
	echo "mysqldump not found." >&2
	echo "(with Debian, \"apt-get install mysql-client\" will help)" >&2
	exit 1
fi

#
# READ TABLE LIST from __DATA__ section at the end of this script
# (http://stackoverflow.com/a/3477269/2983301) 
#
DATA_TABLES=()
while read line; do
	table=$(echo "$line" | cut -d" " -f1)
	echo "$line" | cut -d" " -f5 | grep -qi "DATA"
	test $? -eq 0 && DATA_TABLES+=($table)
done < <(sed '0,/^__DATA__$/d' "$0" | tr -s " ") 

# paranoid check
if [ ${#DATA_TABLES[@]} -lt 5 ]; then
	echo "ERROR: The number of large data tables configured in this script is less than 5." >&2
	exit 1
fi

#
# BACKUP
#
mkdir -p "${DUMPDIR}"

# Read table list from database
echo "Fetching list of existing tables..."
DB_TABLES=$($MYSQL_BATCH -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$DBNAME'" | sort)
DB_TABLE_NUM=$(echo "$DB_TABLES" | wc -l)

PROCESSED_DATA_TABLES=()
i=0

echo "Starting table backups..."
while read table; do
	# large data tables: only store schema
	if elementIn "$table" "${DATA_TABLES[@]}"; then
		dump_opt="--no-data"
		PROCESSED_DATA_TABLES+=($table)
	# configuration tables: full dump
	else
		dump_opt="--extended-insert=FALSE"
	fi
	mysqldump --routines --opt --single-transaction --skip-lock-tables \
		$dump_opt $MYSQL_CONN --tables ${table} >>"${DUMPFILE}"

	# show percentage
	i=$((i+1)); i_percent=$(($i * 100 / $DB_TABLE_NUM))
	if [ $(($i_percent % 12)) -eq 0 ]; then
		echo -n "${i_percent}%"
	else
		if [ $(($i_percent % 2)) -eq 0 ]; then echo -n "."; fi
	fi
done <<<"$DB_TABLES" 

echo -e "\n"
echo "For the following large tables only the schema (without data) was stored:"
for table in "${PROCESSED_DATA_TABLES[@]}"; do echo " - $table"; done

echo 
echo "Compressing backup file..."
gzip -f "${DUMPFILE}"
if [ $? -ne 0 ]; then
	echo -e "\nERROR: Could not compress backup file, see previous messages" >&2
	exit 1
fi

echo -e "\nBackup Completed:\n${DUMPFILE}.gz"

exit

################################################################################
# List of all known table names and a flag indicating data (=large) tables
#

__DATA__
acknowledges              1.3.1    - 2.4.0  DATA
actions                   1.3.1    - 2.4.0
alerts                    1.3.1    - 2.4.0  DATA
application_template      2.1.0    - 2.4.0
applications              1.3.1    - 2.4.0
auditlog                  1.3.1    - 2.4.0  DATA
auditlog_details          1.7      - 2.4.0  DATA
autoreg                   1.3.1    - 1.3.4
autoreg_host              1.7      - 2.4.0
conditions                1.3.1    - 2.4.0
config                    1.3.1    - 2.4.0
dbversion                 2.1.0    - 2.4.0
dchecks                   1.3.4    - 2.4.0
dhosts                    1.3.4    - 2.4.0
drules                    1.3.4    - 2.4.0
dservices                 1.3.4    - 2.4.0
escalations               1.5.3    - 2.4.0
events                    1.3.1    - 2.4.0  DATA
expressions               1.7      - 2.4.0
functions                 1.3.1    - 2.4.0
globalmacro               1.7      - 2.4.0
globalvars                1.9.6    - 2.4.0
graph_discovery           1.9.0    - 2.4.0
graph_theme               1.7      - 2.4.0
graphs                    1.3.1    - 2.4.0
graphs_items              1.3.1    - 2.4.0
group_discovery           2.1.4    - 2.4.0
group_prototype           2.1.4    - 2.4.0
groups                    1.3.1    - 2.4.0
help_items                1.3.1    - 2.1.8
history                   1.3.1    - 2.4.0  DATA
history_log               1.3.1    - 2.4.0  DATA
history_str               1.3.1    - 2.4.0  DATA
history_str_sync          1.3.1    - 2.2.6  DATA
history_sync              1.3.1    - 2.2.6  DATA
history_text              1.3.1    - 2.4.0  DATA
history_uint              1.3.1    - 2.4.0  DATA
history_uint_sync         1.3.1    - 2.2.6  DATA
host_discovery            2.1.4    - 2.4.0
host_inventory            1.9.6    - 2.4.0
host_profile              1.9.3    - 1.9.5
hostmacro                 1.7      - 2.4.0
hosts                     1.3.1    - 2.4.0
hosts_groups              1.3.1    - 2.4.0
hosts_profiles            1.3.1    - 1.9.2
hosts_profiles_ext        1.6      - 1.9.2
hosts_templates           1.3.1    - 2.4.0
housekeeper               1.3.1    - 2.4.0
httpstep                  1.3.3    - 2.4.0
httpstepitem              1.3.3    - 2.4.0
httptest                  1.3.3    - 2.4.0
httptestitem              1.3.3    - 2.4.0
icon_map                  1.9.6    - 2.4.0
icon_mapping              1.9.6    - 2.4.0
ids                       1.3.3    - 2.4.0
images                    1.3.1    - 2.4.0
interface                 1.9.1    - 2.4.0
interface_discovery       2.1.4    - 2.4.0
item_condition            2.3.0    - 2.4.0
item_discovery            1.9.0    - 2.4.0
items                     1.3.1    - 2.4.0
items_applications        1.3.1    - 2.4.0
maintenances              1.7      - 2.4.0
maintenances_groups       1.7      - 2.4.0
maintenances_hosts        1.7      - 2.4.0
maintenances_windows      1.7      - 2.4.0
mappings                  1.3.1    - 2.4.0
media                     1.3.1    - 2.4.0
media_type                1.3.1    - 2.4.0
node_cksum                1.3.1    - 2.2.6
node_configlog            1.3.1    - 1.4.7
nodes                     1.3.1    - 2.2.6
opcommand                 1.9.4    - 2.4.0
opcommand_grp             1.9.2    - 2.4.0
opcommand_hst             1.9.2    - 2.4.0
opconditions              1.5.3    - 2.4.0
operations                1.3.4    - 2.4.0
opgroup                   1.9.2    - 2.4.0
opmediatypes              1.7      - 1.8.21
opmessage                 1.9.2    - 2.4.0
opmessage_grp             1.9.2    - 2.4.0
opmessage_usr             1.9.2    - 2.4.0
optemplate                1.9.2    - 2.4.0
profiles                  1.3.1    - 2.4.0
proxy_autoreg_host        1.7      - 2.4.0
proxy_dhistory            1.5      - 2.4.0
proxy_history             1.5.1    - 2.4.0
regexps                   1.7      - 2.4.0
rights                    1.3.1    - 2.4.0
screens                   1.3.1    - 2.4.0
screens_items             1.3.1    - 2.4.0
scripts                   1.5      - 2.4.0
service_alarms            1.3.1    - 2.4.0
services                  1.3.1    - 2.4.0
services_links            1.3.1    - 2.4.0
services_times            1.3.1    - 2.4.0
sessions                  1.3.1    - 2.4.0
slides                    1.3.4    - 2.4.0
slideshows                1.3.4    - 2.4.0
sysmap_element_url        1.9.0    - 2.4.0
sysmap_url                1.9.0    - 2.4.0
sysmaps                   1.3.1    - 2.4.0
sysmaps_elements          1.3.1    - 2.4.0
sysmaps_link_triggers     1.5      - 2.4.0
sysmaps_links             1.3.1    - 2.4.0
timeperiods               1.7      - 2.4.0
trends                    1.3.1    - 2.4.0  DATA
trends_uint               1.5      - 2.4.0  DATA
trigger_depends           1.3.1    - 2.4.0
trigger_discovery         1.9.0    - 2.4.0
triggers                  1.3.1    - 2.4.0
user_history              1.7      - 2.4.0
users                     1.3.1    - 2.4.0
users_groups              1.3.1    - 2.4.0
usrgrp                    1.3.1    - 2.4.0
valuemaps                 1.3.1    - 2.4.0
