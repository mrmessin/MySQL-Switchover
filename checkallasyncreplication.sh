#!/bin/bash
#
#####################################################################
#   Name: checkallasyncreplication.sh
#
#
# Description:  Script to run through list of databases to check
#               group replication for
#
#####################################################################
#
# Run From Central Monitoring Server
export slave_list=$1

#####################################################
# Script environment
#####################################################
# assign a date we can use as part of the logfile
export DTE=`/bin/date +%m%d%C%y%H%M`

# Get locations
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`

# Set the logfile directory
export LOGPATH=${SCRIPTLOC}/logs
export LOGFILE=checkallasyncreplication_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

export MYSQL_HOME=/opt/mysql

# Get out rdba database password we need
if [ -f "${MYSQL_HOME}/scripts/.rdba" ]; then
   export PASSWD=`cat ${MYSQL_HOME}/scripts/.rdba | /usr/bin/openssl enc -md md5 -d -aes-256-cbc -base64 -nosalt -pass pass:RoltaAdvizeX`
   export MYSQL_PWD=${PASSWD}
else
   echo "ERROR -> rdba password not found! can not process DR test mode."
   #echo "ERROR -> rdba password not found! can not process DR test mode." >> ${LOG}
   exit 8
fi

##############################################################
while read line; do
mysql -u rdba -h${line} -s -e 'SHOW SLAVE STATUS\G' > sstatus

function extract_value {
    FILENAME=$1
    VAR=$2
    grep -w $VAR $FILENAME | awk '{print $2}'
}

Slave_IO_Running=$(extract_value sstatus Slave_IO_Running)
Slave_SQL_Running=$(extract_value sstatus Slave_SQL_Running)

if [ "$Slave_IO_Running" == "No" ] || [ "$Slave_SQL_Running" == "No" ]
then
    echo "Error -> ${line} Async Replication Slave IO or SQL Slave is not Running"
else
    echo "OK -> Replication on ${line} Running"
fi
done < ${slave_list}

exit 0
