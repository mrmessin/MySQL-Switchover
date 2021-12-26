###############################################################################################################
#  Name: mysql_dr_switchover_central.sh
#
# Description:  From central Monitoring server can execute
#               to switchover the primary master to master at slave
#               multiple mysql databases based on file with list of servers 
#
#  Parameters:  text file containing list of nodes to switch master to slave
#               and slave to master
#               ag* when switching ag to be primary
#               dt* when switching dt to be primary
#
#  Examples:    /opt/mysql/software/mysql/scripts/mysql_dr_switchover_central.sh ag_mysql_switchover.txt
#               /opt/mysql/software/mysql/scripts/mysql_dr_switchover_central.sh dt_mysql_switchover.txt
###############################################################################################################
################################################################
# Accept parameter for file with list of nodes to work on
################################################################
export inputfile=$1

echo "Executing MySQL Switchover for Databases in file ${inputfile}  ......."

if [ ! -f "$inputfile" ]
then
   echo "MySQL DB Upgrade Failed -> ${inputfile} does not exist can not process upgrade."
   exit 8
fi

##################################################
# Standards Needed for Provision Script Process
##################################################
# MySQL Locations
export MYSQL_HOME=/opt/mysql
export MYSQL_SOFTWARE=${MYSQL_HOME}/software/mysql

# Get locations
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`

export DTE=`/bin/date +%m%d%C%y%H%M`

# Local hostname
export HOSTNAME=`hostname`

# Set the logfile directory
export LOGPATH=${SCRIPTLOC}/logs
echo "Script Location: ${SRIPTLOC}"
export LOGFILE=mysql_switchover_central_${inputfile}_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#########################################################################################################
# To protect environment a protecton file is utilized that must be removed manually for process to run
#########################################################################################################
if [ -f "${SCRIPTLOC}/.switchover_protection" ]
then
   echo "ERROR -> Script Protection is on Please remove file .switchover_protection and re-execute if you really want to run process"
   echo "ERROR -> Script Protection is on Please remove file .switchover_protection and re-execute if you really want to run process" >> ${LOG}
   exit 8
fi

# go through each node in the list in the file and execute upgrade
while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export slavenode=`echo ${line}| awk '{print $1}'`
   export masternode=`echo ${line}| awk '{print $2}'`

   echo "Processing ${slavenode} to Master and ${masternode} to Slave."
   echo "Processing ${slavenode} to Master and ${masternode} to Slave." >> ${LOG}

   ${SCRIPTLOC}/mysql_switchover.sh ${masternode} ${slavenode} ${LOG}
   
   # Check if Upgrades are to Continue
   if [ $? -eq 0 ]; then
       echo "Database Switchover Successful, ${slavenode} to Master and ${masternode} to Slave."
       echo "Database Switchover Successful, ${slavenode} to Master and ${masternode} to Slave." >> ${LOG}
   else
       echo "Error -> Database Switchover Failed, ${slavenode} to Master and ${masternode} to Slave."
       echo "Error -> Database Switchover Failed, ${slavenode} to Master and ${masternode} to Slave." >> ${LOG}
       exit 8
   fi
done < "${inputfile}"

# To protect environment a protecton file is utilized that must be removed manually for process to run
if [ -f "${SCRIPTLOC}/.switchover_protection" ]; then
   echo "OK -> Protection File Created"
   echo "OK -> Protection File Created" >> ${LOG}
else
   echo "ERROR -> Protection File Not Created Create File ${SCRIPTLOC}/.switchover_protection"
   echo "ERROR -> Protection File Not Created Create File ${SCRIPTLOC}/.switchover_protection" >> ${LOG}
fi

exit 0
