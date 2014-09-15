#!/bin/bash
# NAME
#     zabbix-mysql-backupconf.sh - Configuration Backup for Zabbix 2.0 w/MySQL
#
# SYNOPSIS
#     This is a MySQL configuration backup script for Zabbix v2.0 oder 2.2.
#     It does a full backup of all configuration tables, but only a schema
#     backup of large data tables.
#
#     The original script was written by Ricardo Santos and published at
#     http://zabbixzone.com/zabbix/backuping-only-the-zabbix-configuration/
#     and
#     https://github.com/xsbr/zabbixzone/blob/master/zabbix-mysql-backupconf.sh
#
#     Credits for some suggestions concerning the original script to:
#      - Ricardo Santos
#      - Oleksiy Zagorskyi (zalex)
#      - Petr Jendrejovsky
#      - Jonathan Bayer
#      - Andreas Niedermann (dre-)
#
# HISTORY
#     v0.6 - 2014-09-15 Updated the table list for use with zabbix v2.2.3
#     v0.5 - 2013-05-13 Added table list comparison between database and script
#     v0.4 - 2012-03-02 Incorporated mysqldump options suggested by Jonathan Bayer
#     v0.3 - 2012-02-06 Backup of Zabbix 1.9.x / 2.0.0, removed unnecessary use of
#                       variables (DATEBIN etc) for commands that use to be in $PATH
#     v0.2 - 2011-11-05
#
# AUTHOR
#     Jens Berthold (maxhq), 2013


#
# CONFIGURATION
#

# mysql database
DBHOST="1.2.3.4"
DBNAME="zabbix"
DBUSER="zabbix"
DBPASS="password"

# backup target path
#MAINDIR="/var/lib/zabbix/backupconf"
# following will store the backup in a subdirectory of the current directory
MAINDIR="`dirname \"$0\"`"

#
# CONSTANTS
#

# configuration tables
CONFTABLES=( actions application_template applications autoreg_host conditions \
config dbversion dchecks dhosts drules dservices escalations expressions functions \
globalmacro globalvars graph_discovery graph_theme graphs graphs_items group_discovery \
group_prototype groups host_discovery host_inventory hostmacro hosts \
hosts_groups hosts_templates housekeeper httpstep httpstepitem httptest \
httptestitem icon_map icon_mapping ids images interface interface_discovery \
item_discovery items items_applications maintenances maintenances_groups \
maintenances_hosts maintenances_windows mappings media media_type node_cksum \
nodes opcommand opcommand_grp opcommand_hst opconditions operations opgroup \
opmessage opmessage_grp opmessage_usr optemplate profiles proxy_autoreg_host \
proxy_dhistory proxy_history regexps rights screens screens_items scripts \
service_alarms services services_links services_times sessions slides \
slideshows sysmap_element_url sysmap_url sysmaps sysmaps_elements \
sysmaps_link_triggers sysmaps_links timeperiods trigger_depends trigger_discovery \
triggers user_history users users_groups usrgrp valuemaps )

# tables with large data
DATATABLES=( acknowledges alerts auditlog_details auditlog events \
history history_log history_str history_str_sync history_sync history_text \
history_uint history_uint_sync trends trends_uint )

DUMPDIR="${MAINDIR}/`date +%Y%m%d-%H%M`"
DUMPFILE="${DUMPDIR}/zabbix-conf-backup-`date +%Y%m%d-%H%M`.sql"

#
# CHECKS
#
if [ ! -x /usr/bin/mysqldump ]; then
    echo "mysqldump not found."
    echo "(with Debian, \"apt-get install mysql-client\" will help)"
    exit 1
fi

#
# compare table list between script and database
#
FILE_TABLES_LIVE=`mktemp`
FILE_TABLES=`mktemp`

# Get all current Zabbix tables from databse
mysql -h ${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBNAME} --batch --silent \
    -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$DBNAME'" \
    | sort >> $FILE_TABLES_LIVE

# Merge CONFTABLES and DATATABLES into one array
allTables=( "${CONFTABLES[@]}" "${DATATABLES[@]}" )
printf '%s\n' "${allTables[@]}" | sort >> $FILE_TABLES

difference=`diff --suppress-common-lines $FILE_TABLES $FILE_TABLES_LIVE | grep -v "^\w"`

if [ ! -z "$difference" ]; then
    echo -e "The Zabbix database differs from the configuration in this script."
    if [ `echo "$difference" | grep -c "^>"` -gt 0 ]; then
            echo -e "\nThese additional tables where found in '$DBNAME' on $DBHOST:"
            echo "$difference" | grep "^>" | sed 's/^>/ -/gm'
    fi
    if [ `echo "$difference" | grep -c "^<"` -gt 0 ]; then
            echo -e "\nThese configured tables are missing in '$DBNAME' on $DBHOST:"
            echo "$difference" | grep "^<" | sed 's/^</ -/gm'
    fi
    rm $FILE_TABLES_LIVE; rm $FILE_TABLES
    exit
fi
rm $FILE_TABLES_LIVE; rm $FILE_TABLES

#
# BACKUP
#
mkdir -p "${DUMPDIR}"

>"${DUMPFILE}"

# full backup of configuration tables
echo "Full backup of configuration tables:"
for table in ${CONFTABLES[*]}; do
    echo " - ${table}"
    mysqldump --routines --opt --single-transaction --skip-lock-tables --extended-insert=FALSE \
            -h ${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBNAME} --tables ${table} >>"${DUMPFILE}"
done
# scheme backup of large data tables
echo "Scheme backup of data tables:"
for table in ${DATATABLES[*]}; do
    echo " - ${table}"
    mysqldump --routines --opt --single-transaction --skip-lock-tables --no-data \
            -h ${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBNAME} --tables ${table} >>"${DUMPFILE}"
done

echo "Compressing backup file ${DUMPFILE}..."
gzip -f "${DUMPFILE}"

echo
echo "Backup Completed - ${DUMPDIR}"
echo "Hit ENTER"
read
