#!/bin/bash
##############################################################################
# Script:      mysql_switchover 
#
# Description: MySQL script to automate switchover process
#
# Parameters:  Current Master / Current Slave
# 
# Usage:       ./mysql_switchover <MASTER> <SLAVE> 
#              ./mysql_switchover dtlprdmyp25 aglprdmyp25 
# 
##############################################################################
#Set Master and Slave Variable passed from command line
export master=$1
export slave=$2
export LOG=$3

#Set MySQL Home Location
export MYSQL_HOME=/opt/mysql
export MYSQL_SOFTWARE=/opt/mysql/software/mysql

export DTE=`/bin/date +%m%d%C%y%H%M`

if [ "${LOG}" = "" ]; then
   # Set the logfile directory
   export LOGPATH=${SCRIPTLOC}/logs
   export LOGFILE=mysql_switchover_${master}_${slave}_${DTE}.log
   export LOG=$LOGPATH/$LOGFILE
fi

echo "Using Logfile ${LOG} for ${master} to ${slave}" 
echo "Using Logfile ${LOG} for ${master} to ${slave}" >> ${LOG}

#############################################################################
# Makes Sure arguments are passed to script
#############################################################################
# check if Master host was passed
if [ -z "$master" ]
then
   echo "Switch Over Script Failed -> MySQL Master Not Defined."
   echo "Usage: ./mysql_switchover <MASTER> <SLAVE> "
   echo ""
   exit 8
fi

# Check is slave host was passed
if [ -z "$slave" ]
then
   echo "Switch Over Script Failed -> MySQL Slave Not Defined."
   echo "Usage: ./mysql_switchover <MASTER> <SLAVE> "
   echo ""
   exit 8
fi

###########################################################################
# Get Passwords for RPL_USER and rdba needed for processing
###########################################################################
##########################################
# rpl_user
if [ -f "${MYSQL_SOFTWARE}/scripts/.rpl_user" ]; then
   export RPL_USER=`cat ${MYSQL_SOFTWARE}/scripts/.rpl_user | openssl enc -base64 -d -aes-256-cbc -md md5 -nosalt -pass pass:RoltaAdvizeX`
else
   echo "ERROR -> Switchover Failed. --> replication user password not found!"
   echo "ERROR -> Switchover Failed. --> replication user password not found!" >> ${LOG}
   exit 8
fi

##########################################
# rdba
if [ -f "${MYSQL_HOME}/scripts/.rdba" ]; then
   export PASSWD=`cat ${MYSQL_HOME}/scripts/.rdba | /usr/bin/openssl enc -md md5 -d -aes-256-cbc -base64 -nosalt -pass pass:RoltaAdvizeX`
   export MYSQL_PWD=${PASSWD}
else
   echo "ERROR -> rdba password not found! can not process DR test mode."
   #echo "ERROR -> rdba password not found! can not process DR test mode." >> ${LOG}
   exit 8
fi

#########################################################################################################
# To protect environment a protecton file is utilized that must be removed manually for process to run
#########################################################################################################
if [ -f "${SCRIPTLOC}/.switchover_protection" ]
then
   echo "ERROR -> Script Protection is on Please remove file .switchover_protection and re-execute if you really want to run process"
   #echo "ERROR -> Script Protection is on Please remove file .switchover_protection and re-execute if you really want to run process" >> ${LOG}
   exit 8
fi

##############################################################
# Verify proper nodes passed
##############################################################
echo ""
echo "Current Master = $master Current Slave = $slave"
echo "Current Master = $master Current Slave = $slave" >> ${LOG}

##############################################################
# Verify Slave passed is truely a slave
##############################################################
SLAVE_CHECK=$(mysql -urdba -h${slave} -ANe "SHOW SLAVE STATUS;")
#echo ${SLAVE_CHECK}

if [ -z "${SLAVE_CHECK}" ]
then
   echo "ERROR -> Switch Over Script Failed -> MySQL Slave passed ${slave} is not an active slave."
   echo "ERROR -> Switch Over Script Failed -> MySQL Slave passed ${slave} is not an active slave." >> ${LOG}
   exit 8
fi

#Desired output for slave caught up
export DOUT='Slave_SQL_Running_State: Slave has read all relay log; waiting for more updates'

#Set Slave status
export SLAVE_STATUS=$(mysql -urdba -h${slave} -se "SHOW SLAVE STATUS\G;"|grep Slave_SQL_Running_State )

#Strip carriage return from variable
export SLAVE_STATUS=$(echo ${SLAVE_STATUS}|tr -d '\n')

if [ "${SLAVE_STATUS}" != "${DOUT}" ]; then
   echo "Async Slave on ${slave} is not running.... Aborting Process......" 
   echo "Async Slave on ${slave} is not running.... Aborting Process......" >> ${LOG}
   exit 8
fi

###########################################################################
# Check if Group Replication Involved if so Make sure at First Node 
# As the Current Master Must be at first node otherwise we do not
# Want anything but the first node in group to become a slave
# We can switch it at this point if MySQL 8 othwise it has to be fixed
###########################################################################

# Check if master is in group replication if so is PRIMARY the node we are switching?  If No switch Primary
export primary=`${MYSQL_HOME}/current/bin/mysql -urdba -h${master} -N -s -e "SELECT member_host FROM performance_schema.global_status JOIN performance_schema.replication_group_members WHERE variable_name = 'group_replication_primary_member' AND member_id=variable_value ; " `

if [ "${primary}" = "" ]; then
   echo "OK -> No Group Replication No Action Needed!"
   echo "OK -> No Group Replication No Action Needed!" >> ${LOG}
else
   if [[ ${primary} =~ "${master}" ]]; then
      echo "OK -> ${master} is primary ${primary}, ok!"
      echo "OK -> ${master} is primary ${primary}, ok!" >> ${LOG}
   else
      echo "WARNING -> ${master} is not primary ${primary}, fixing......"
      echo "WARNING -> ${master} is not primary ${primary}, fixing......" >> ${LOG}
      export mysqlcmd="select member_id from performance_schema.replication_group_members where member_host like '%${master}%';"
      export primary_id=`${MYSQL_HOME}/current/bin/mysql -urdba -h${master} -s -N -e "${mysqlcmd}"`
      ${MYSQL_HOME}/current/bin/mysql -urdba -h${master} -e "SELECT group_replication_set_as_primary('${primary_id}');"

      # Check Primary was changed to master node
      export primary=`${MYSQL_HOME}/current/bin/mysql -urdba -h${master} -N -s -e "SELECT member_host FROM performance_schema.global_status JOIN performance_schema.replication_group_members WHERE variable_name = 'group_replication_primary_member' AND member_id=variable_value ; " `

      if [[ ${primary} =~ "${master}" ]]; then
         echo "OK -> Primary Changed to -> ${primary}"
         echo "OK -> Primary Changed to -> ${primary}" >> ${LOG}
      else
         echo "ERROR -> ${master} is not primary ${primary}, Exiting......"
         echo "ERROR -> ${master} is not primary ${primary}, Exiting......" >> ${LOG}
         exit 8
      fi
   fi
fi

# Check if async slave at the Primary if so then we should not be doing switch if not then we can switch
# This will Handle Regular primary async replication switchover as long as we are not an existing slave in the async confg this will turn
# any slave to a cascaded slave and that is ok.
PRIMARYSLAVE_CHECK=$(mysql -urdba -h${master} -ANe "SHOW SLAVE STATUS;")
#echo ${PRIMARYSLAVE_CHECK}

if [ "${PRIMARYSLAVE_CHECK}" = "" ]
then
   echo "The ${master} does not have async slave can continue."
   echo "The ${master} does not have async slave can continue." >> ${LOG}
else
   echo "ERROR -> Switch Over Script Failed -> MySQL Primary passed ${master} is an active slave."
   echo "ERROR -> Switch Over Script Failed -> MySQL Slave passed ${master} is an active slave." >> ${LOG}
   exit 8
fi

##############################################################
# Set Master into state where no Updates can happen
##############################################################
echo ""
echo "Placing Current Master ${master} in Read Only!  This is so we Stop Writes During Switchover"
echo "" >> ${LOG}
echo "Placing Current Master ${master} in Read Only!  This is so we Stop Writes During Switchover" >> ${LOG}

mysql -urdba -h${master} <<EOFMYSQL
FLUSH TABLES WITH READ LOCK;SET GLOBAL read_only = 1;SELECT @@hostname as "Host Name" ,if(@@read_only=0,'R/W','R') User,if(@@super_read_only=0,'R/W','R') "Super User";
EOFMYSQL

# Check if Command Was Successful for setting current master to prepare for switchover
if [ $? -eq 0 ]; then
   echo "OK -> Setting Master to stop writes on ${master} ok, continuing"
   echo "OK -> Setting Master to stop writes on ${master} ok, continuing" >> ${LOG}
else
   echo "ERROR -> Setting Master to stop writes on ${master} not ok, aborting process"
   echo "ERROR -> Setting Master to stop writes on ${master} not ok, aborting process" >> ${LOG}
   exit 8
fi

#############################################################
# Verify Current Master is now Read Only!   
#############################################################
# Check Super Read Only
#export superreadonlystate=`mysql -u rdba -h${master} --silent -e "SELECT @@GLOBAL.super_read_only;"`
#
#if [[ ${superreadonlystate} != '1' ]]
# then
#   echo "ERROR -> Node ${master} Reports -> ${superreadonlystate} should be 1/ON please Check!, Exiting....."
#   exit 8
#fi

# Check Read only
export readonlystate=`mysql -u rdba -h${master} --silent -e "SELECT @@GLOBAL.read_only;"`

if [[ ${readonlystate} != '1' ]]
  then
   echo "ERROR -> Node ${master} Reports -> ${readonlystate} should be 1/ON please Check!, Exiting....."
   echo "ERROR -> Node ${master} Reports -> ${readonlystate} should be 1/ON please Check!, Exiting....." >> ${LOG}
   exit 8
fi

# Sleep for a few seconds before chacking any lag after putting master in read only
sleep 5

################################################################################
# Verify Slave is all caught up
################################################################################
echo "---------------------------------------------------------------------------------"
echo "Verifying slave ${slave} has applied all updates from Master ${master} "
echo "---------------------------------------------------------------------------------" >> ${LOG}
echo "Verifying slave ${slave} has applied all updates from Master ${master} " >> ${LOG}

#Desired output for slave caught up
export DOUT='Slave_SQL_Running_State: Slave has read all relay log; waiting for more updates'

#Set Slave status
export SLAVE_STATUS=$(mysql -urdba -h${slave} -se "SHOW SLAVE STATUS\G;"|grep Slave_SQL_Running_State )

#Strip carriage return from variable
export SLAVE_STATUS=$(echo ${SLAVE_STATUS}|tr -d '\n')

# For testing the loop
#SLAVE_STATUS=""

while [ "${SLAVE_STATUS}" != "${DOUT}" ]
do
  echo "Still Applying updates will sleep and check again: cntrl c to exit if needed"
  sleep 5
  #Set Slave status again
  SLAVE_STATUS=$(mysql -urdba -h$slave -se "SHOW SLAVE STATUS\G;"|grep Slave_SQL_Running_State )
  #Strip carriage return from variable
  SLAVE_STATUS=$(echo ${SLAVE_STATUS}|tr -d '\n')
  #For testing loop
  #SLAVE_STATUS=""
done

echo ""
echo "OK -> ${slave} Slave Status OK -> ${SLAVE_STATUS}"
echo "" >> ${LOG}
echo "OK -> ${slave} Slave Status OK -> ${SLAVE_STATUS}" >> ${LOG}

# Debug
#echo "output above should read: "
#echo "Slave_SQL_Running_State: Slave has read all relay log; waiting for more updates"
#echo "If not exit out and check why all logs have not applied to the Slave"
#echo ""

#read -p "Press enter to continue or cntrl c to exit "

echo "-----------------------------------------------------------------------------------------------"
echo "Checking Slave Apply Lag for ${slave}: "
echo "-----------------------------------------------------------------------------------------------" >> ${LOG}
echo "Checking Slave Apply Lag for ${slave}: " >> ${LOG}
sleep 1

# Desired output for Seconds behind Master
export DOUT2='Seconds_Behind_Master: 0'

#Set LAG_CHECK
LAG_CHECK=$(mysql -urdba -h${slave} -e "SHOW SLAVE STATUS\G"| grep 'Seconds_Behind_Master')
#echo ${LAG_CHECK}

#Strip carriage return from variable
LAG_CHECK=$(echo ${LAG_CHECK}|tr -d '\n')

#For testing
#LAG_CHECK=5

while [ "${LAG_CHECK}" != "${DOUT2}" ]
do
  echo "Still Applying updates will sleep and check again: cntrl c to exit if needed"
  echo "Still Applying updates will sleep and check again: cntrl c to exit if needed" >> ${LOG}
  sleep 5
  #Set Slave status again
  LAG_CHECK=$(mysql -urdba -h${slave} -e "SHOW SLAVE STATUS\G"| grep 'Seconds_Behind_Master')
  #Strip carriage return from variable
  LAG_CHECK=$(echo ${LAG_CHECK}|tr -d '\n')
  #For testing loop
  #LAG_CHECK=5
done

echo ""
echo "INFO -> Slave Lag OK on ${slave} -> ${LAG_CHECK}"
echo "" >> ${LOG}
echo "INFO -> Slave Lag OK on ${slave} -> ${LAG_CHECK}" >> ${LOG}

#echo "output above should read: "
#echo "Seconds_Behind_Master: 0"
#echo "If not exit out and check why Slave ${slave} is behind Master ${master} "
#echo ""
#read -p "Press enter to continue or cntrl c to exit "

#######################################################
# Reset Current async slave so it can be a master
#######################################################
echo ""
echo "Resetting Current Slave Configuration on Slave ${slave}"
echo "" >> ${LOG}
echo "Resetting Current Slave Configuration on Slave ${slave}" >> ${LOG}

mysql -urdba -h${slave}<<EOFMYSQL
STOP SLAVE; RESET SLAVE ALL FOR CHANNEL ''; 
EOFMYSQL

# Check if Command Was Successful for setting reset slave
if [ $? -eq 0 ]; then
   echo "OK -> Setting Current Slave to stop and reset on ${slave} ok, continuing"
   echo "OK -> Setting Current Slave to stop and reset on ${slave} ok, continuing" >> ${LOG}
else
   echo "ERROR -> Setting Current Slave to stop and reset on ${slave} not ok, aborting process"
   echo "ERROR -> Setting Current Slave to stop and reset on ${slave} not ok, aborting process" >> ${LOG}
   exit 8
fi

########################################################
# Check that the is no More Slave in Place on Slave
########################################################
# NEED A BETTER SLAVE CHECK?
SLAVE_CHECK=$(mysql -urdba -h${slave} -ANe "SHOW SLAVE STATUS;")
#echo ${SLAVE_CHECK}

if [ -z "${SLAVE_CHECK}" ]
then
   echo "OK -> MySQL Slave ${slave} Cleared and is no Longer a Slave."
   echo "OK -> MySQL Slave ${slave} Cleared and is no Longer a Slave." >> ${LOG}
else
   echo "ERROR -> MySQL Slave ${slave} is not Cleared ${SLAVE_CHECK}"
   echo "ERROR -> MySQL Slave ${slave} is not Cleared ${SLAVE_CHECK}" >> ${LOG}
   exit 8
fi

########################################################################################
# Get New Master Master file and log position we will need this for new slave position
########################################################################################
MASTER_STATUS=$(mysql -urdba -h${slave} -ANe "SHOW MASTER STATUS;" | awk '{print $1 " " $2}')
#echo ${MASTER_STATUS}

# Check getting new master file and log position was successful
if [ $? -eq 0 ]; then
   echo "Gettng the master status on ${slave} ok, continuing"
   echo "Getting the master status on ${slave} ok, continuing" >> ${LOG}
else
   echo "Getting the master status on ${slave} not ok, aborting process"
   echo "Getting the master status on ${slave} not ok, aborting process" >> ${LOG}
   exit 8
fi

LOG_FILE=$(echo ${MASTER_STATUS} | cut -f1 -d ' ')
LOG_POS=$(echo ${MASTER_STATUS} | cut -f2 -d ' ')

echo "New Master log file on ${slave} is ${LOG_FILE} and log position is $LOG_POS"
echo "New Master log file on ${slave} is ${LOG_FILE} and log position is $LOG_POS" >> ${LOG}

#Just to verify sql for testing
# code at top and put into variable $RPL_USER
sql="CHANGE MASTER TO
MASTER_HOST = '${slave}',
MASTER_USER = 'rpl_user',
MASTER_PASSWORD = '${RPL_USER}',
MASTER_LOG_FILE = '${LOG_FILE}',
MASTER_LOG_POS = ${LOG_POS},
MASTER_SSL=1,
MASTER_SSL_CA = '/opt/mysql/data/data/ca.pem',
MASTER_SSL_CAPATH = '/opt/mysql/data/data',
MASTER_SSL_CERT = '/opt/mysql/data/data/client-cert.pem',
MASTER_SSL_KEY = '/opt/mysql/data/data/client-key.pem' ;"
#echo ""
#echo $sql
#echo ""

mysql -urdba -h${master} <<EOFMYSQL
CHANGE MASTER TO MASTER_HOST = '$slave',MASTER_USER = 'rpl_user',MASTER_PASSWORD = '${RPL_USER}',MASTER_LOG_FILE = '${LOG_FILE}',MASTER_LOG_POS = ${LOG_POS},MASTER_SSL=1,MASTER_SSL_CA = '/opt/mysql/data/data/ca.pem',MASTER_SSL_CAPATH = '/opt/mysql/data/data',MASTER_SSL_CERT = '/opt/mysql/data/data/client-cert.pem',MASTER_SSL_KEY = '/opt/mysql/data/data/client-key.pem';SET GLOBAL read_only = 0;UNLOCK TABLES;start slave;
EOFMYSQL

# Check if Command Was Successful for Setting new slave (old master) position and starting slave
if [ $? -eq 0 ]; then
   echo "OK -> Setting new slave position and starting slave on ${master} ok, continuing"
   echo "OK -> Setting new slave position and starting slave on ${master} ok, continuing" >> ${LOG}
else
   echo "ERROR -> Setting new slave position and starting slave on ${master} not ok, aborting process"
   echo "ERROR -> Setting new slave position and starting slave on ${master} not ok, aborting process" >> ${LOG}
   exit 8
fi

sleep 5

############################################################################
# All Done with Switch over time to check async slave and group replication
############################################################################
echo ""
echo "SUCCESS -> Switchover New Master is ${slave} and New Slave is ${master} is complete"
echo ""
echo "Time to Check if Async Slave ok and Group Replication OK!"
echo "" >> ${LOG}
echo "Switchover New Master is ${slave} and New Slave is ${master} is complete" >> ${LOG}
echo "" >> ${LOG}
echo "Time to Check if Async Slave ok and Group Replication OK!" >> ${LOG}
sleep 2

####################################################
# Check Async Replication on Old Master (new slave)
####################################################
# GET A BETTER ACTUAL CHECK HERE!
echo ""
echo "Checking Async Slave Status on New Slave (old master) -> ${master}" 
echo "" >> ${LOG}
echo "Checking Async Slave Status on New Slave (old master) -> ${master}" >> ${LOG}
mysql -urdba -h${master} -e "SHOW SLAVE STATUS\G;" | grep 'Running'
mysql -urdba -h${master} -e "SHOW SLAVE STATUS\G;" | grep 'Running' >> ${LOG}

echo ""
echo "All above should report Yes If not after script completes  "
echo "Log onto slave and resolve any issues"
echo ""
echo "" >> ${LOG}
echo "All above should report Yes If not after script completes  " >> ${LOG}
echo "Log onto slave and resolve any issues" >> ${LOG}
echo "" >> ${LOG}
sleep 7


###############################################
# Group Replication OK Old Master (new slave)
###############################################
# PUT IN GROUP REPLICATION CHECK FROM DR PROCESS HERE !!!!!
echo ""
echo "Checking Group Replication in Old Master (new slave) -> ${master}"
echo ""
echo "" >> ${LOG}
echo "Checking Group Replication in Old Master (new slave) -> ${master}" >> ${LOG}
echo "" >> ${LOG}
sleep 3

mysql -urdba -h$master <<EOFMYSQL
SELECT * FROM performance_schema.replication_group_members;
EOFMYSQL

echo ""
echo ""

###############################################
# Group Replication OK Old Slave (new master)
###############################################
# PUT IN GROUP REPLICATION CHECK FROM DR PROCESS HERE !!!!!
echo ""
echo "Checking Group Replication in Old Slave (new Master) -> ${slave}"
echo ""
sleep 3

mysql -urdba -h$slave <<EOFMYSQL
SELECT * FROM performance_schema.replication_group_members;
EOFMYSQL

###############################################################
# Now we can set the old master (new slave) to read only 
# and no super read only so slave will operate
###############################################################
echo ""
echo "Placing New Slave $master in Read Only! It Should Already be in Read Only but Doing Again to be Sure."
echo ""
sleep 3
mysql -urdba -h$master<<EOFMYSQL
FLUSH TABLES WITH READ LOCK;SET GLOBAL read_only = 1;SET GLOBAL super_read_only=0;SELECT @@hostname as "Host Name" ,if(@@read_only=0,'R/W','R') User,if(@@super_read_only=0,'R/W','R') "Super User";
EOFMYSQL

# Check if Command Was Successful for locking new slave for read only
if [ $? -eq 0 ]; then
   echo "Setting new slave for read only on ${master} ok, continuing"
   echo "Setting new slave for read only on ${master} ok, continuing" >> ${LOG}
else
   echo "Setting new slave for read only on ${master} not ok, aborting process"
   echo "Setting new slave for read only on ${master} not ok, aborting process" >> ${LOG}
   exit 8
fi

######################################################################
# Open up new master (old slave) to have read/write to be new master
######################################################################
echo ""
echo "Placing New Master $slave in R/W"
echo ""
sleep 3
mysql -urdba -h$slave<<EOFMYSQL
SET GLOBAL read_only = 0;UNLOCK TABLES;SELECT @@hostname as "Host Name" ,if(@@read_only=0,'R/W','R') User,if(@@super_read_only=0,'R/W','R') "Super User";
EOFMYSQL

# Check if Command Was Successful for unlocking new master for read/write
if [ $? -eq 0 ]; then
   echo "Setting new master for read/write on ${slave} ok, continuing"
   echo "Setting new master for read/write on ${slave} ok, continuing" >> ${LOG}
else
   echo "Setting new master for read/write on ${slave} not ok, aborting process"
   echo "Setting new master for read/write on ${slave} not ok, aborting process" >> ${LOG}
   exit 8
fi

# Put protection file back in place now that the process has run
touch ${SCRIPTLOC}/.switchover_protection

# To protect environment a protecton file is utilized that must be removed manually for process to run
if [ -f "${SCRIPTLOC}/.switchover_protection" ]; then
   echo "OK -> Protection File Created"
   #echo "OK -> Protection File Created" >> ${LOG}
else
   echo "ERROR -> Protection File Not Created Create File ${SCRIPTLOC}/.switchover_protection"
   #echo "ERROR -> Protection File Not Created Create File ${SCRIPTLOC}/.switchover_protection" >> ${LOG}
fi

echo ""
echo "Switchover Script Complete"
echo "New Master is ${slave} and New Slave is ${master}"
echo "" >> ${LOG}
echo "Switchover Script Complete" >> ${LOG}
echo "New Master is ${slave} and New Slave is ${master}" >> ${LOG}

exit 0
