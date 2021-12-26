export host_list=$1

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
mysql -u rdba -h$line <<EOFMYSQL
SELECT @@hostname as "Host Name" ,if(@@read_only=0,'R/W','R') User,if(@@super_read_only=0,'R/W','R') "Super User";
EOFMYSQL
done < ${host_list}

