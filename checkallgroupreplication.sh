#!/bin/bash
#
#####################################################################
#   Name: checkallgroupreplication.sh
#
#
# Description:  Script to run through list of databases to check
#               group replication for
#
#####################################################################
#
# Run From Central Monitoring Server
export host_list=$1

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
export LOGFILE=checkallgroupreplication_${DTE}.log
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

   while read line; do
      ########################################################
      # Assign the nodename
      export nodename=`echo ${line}| awk '{print $1}'`
      export masternode=`echo ${line}| awk '{print $2}'`

      while read a b
      do
         if [ ${b} != "ONLINE" ]; then
            echo "Mysql Group Replication ${b} -> Please Check the Group Slave for ${nodename}"
            #echo "Mysql Group Replication ${b} -> Please Check the Group Slave for ${nodename}" >> ${LOG}
         fi
      done < <(echo "SELECT MEMBER_HOST,MEMBER_STATE FROM performance_schema.replication_group_members where MEMBER_HOST like (select concat(@@hostname,'%'));" | ${MYSQL_HOME}/current/bin/mysql -u rdba -h${nodename} -s)
   done < ${host_list}

exit 0
