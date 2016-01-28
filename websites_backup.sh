#!/bin/bash
BACKUP_DIR_MAIN="/etc/data/backup"
ERROR_LOG=/etc/data/backup/backup.log
WEBSITES_PATH=/etc/data/docker/docker_webserver/websites/ #With trailing slash

MYSQL_HOST="127.0.0.1"
MYSQL_USER="bck_user"
MYSQL=/usr/bin/mysql
MYSQL_PASSWORD="<mysql_pwd>"
MYSQLDUMP=/usr/bin/mysqldump

SSH_HOST=""
SSH_USER=""
SSH_PORT="22"
SSH_BCK_FOLDER="/etc/data/ws" #No trailing slash

FTP_HOST=""
FTP_USER=""
FTP_PWD=""
FTP_PATH=""

CHECKS_EMAIL_ALERT="email@domain.com"
CHECK_FREE_SPACE=5 #Gb
#--------------------------------------
TIMESTAMP=$(date +"%F")
BACKUP_DIR="$BACKUP_DIR_MAIN/$TIMESTAMP"

statusDb=0
statusFiles=0

function backupDb(){
  db=$2
 
  $MYSQLDUMP --force -h $MYSQL_HOST --opt --user=$MYSQL_USER -p$MYSQL_PASSWORD --databases $db | gzip > "$BACKUP_DIR/mysqldump_$db.gz"
  statusDb=`echo $?`
  if [ $statusDb != 0 ]; then
    dumpLog "Error on $db dump!"
  fi

  copyRemote "$BACKUP_DIR/mysqldump_$db.gz"
}

function sendEmail() {
/usr/lib/sendmail -oi -t -f "website_backup@server.com" <<____HERE
From: Website Backup Service <website_backup@server.com>
To: To <$CHECKS_EMAIL_ALERT>
Subject: Website_backup ALERT

$1
____HERE

}

function checkFreeSpace() {
  freeSpace=$(df -k /tmp | tail -1 | awk '{print $4}') #Bytes
  freeSpace=$((freeSpace / 1024)) #Mb
  chkGb=$((CHECK_FREE_SPACE*1024))

  if test $freeSpace -lt $chkGb; then
    dumpLog "Free space under configured threshold"
    sendEmail "Free space under configured threshold - Free space $freeSpace while configured threshold is $chkGb"
  fi
}

function backupFiles(){
  fileName=$(echo "$1" | sed -e 's#/$##')  #Remove trailing slash
  fileName=${fileName##*/}

  tar zcfP $BACKUP_DIR/$fileName.tgz $1

  statusFiles=`echo $?`
  if [ $statusFiles != 0 ]; then
    dumpLog "Error on $fileName compress!"
  fi

  copyRemote "$BACKUP_DIR/$fileName.tgz"
}

function backupWebsite(){
  statusDb=99
  statusFiles=99

  #Making dir
  mkdir -p "$BACKUP_DIR"

  #Backup website
  backupFiles $1
 
  #Backup DB 
  if [ -f "$1/dbname.backup" ]
  then
    dbname=`cat $1/dbname.backup`
    dumpLog "Db file find, start backup of $dbname"
    backupDb $1 $dbname
  else
    statusDb=0 #If I don't have DB to backup assign true to variable
  fi
  
  #Status check and remove old 
  if [ "$statusDb" == 0 ] && [ "$statusFiles" == 0 ]; then
    fileName=$(basename "$1")
    dumpLog "Backup successfull, I'm going to remove old backups"
    cleanOld $fileName $dbname
  fi

}

function copyRemote(){
  #Check SSH
  if [ ! -x "$SSH_HOST" -a "$SSH_HOST" ]; then
    dumpLog "Working on SSH"
    copyRemoteSSH $1
  fi

  #Check FTP
  if [ ! -x "$FTP_HOST" -a "$FTP_HOST" ]; then
    dumpLog "Working on FTP"
    copyRemoteFTP $1
  fi
}

function copyRemoteSSH(){
  dumpLog "Clean old remote"
  ssh -p $SSH_PORT $SSH_USER@$SSH_HOST "find $SSH_BCK_FOLDER -mtime +10 -exec rm -rf {} \;" 2>&1

  dumpLog "Create folder $TIMESTAMP"
  ssh -p $SSH_PORT $SSH_USER@$SSH_HOST "if [ ! -d $SSH_BCK_FOLDER/$TIMESTAMP ]; then mkdir $SSH_BCK_FOLDER/$TIMESTAMP; fi" 2>&1

  dumpLog "Copy $1 to $SSH_HOST"
  scp -P $SSH_PORT $1 $SSH_USER@$SSH_HOST:$SSH_BCK_FOLDER/$TIMESTAMP/ 2>&1
}

function copyRemoteFTP(){
  BASEDIR=$(dirname $1)
  BASENAME=$(basename $1)
  
  dumpLog "Copy $1 to $FTP_HOST"

  ftp -A -n $FTP_HOST << END_SCRIPT | tee -a $ERROR_LOG
  quote USER $FTP_USER
  quote PASS $FTP_PWD
  lcd $BASEDIR
  cd $FTP_PATH
  mkdir $TIMESTAMP
  cd $TIMESTAMP
  put $BASENAME 
  quit 
END_SCRIPT
}

function cleanOld(){
  dumpLog "Remove old backups > 15 days"
  find $BACKUP_DIR_MAIN/* -name "*$1*" -mtime +30 -exec rm {} \;
}

function dumpLog(){
  now=$(date +"%F %r")
  echo "$now - $1" >> $ERROR_LOG
}
#--------------------------------------

#-----------Main entrypoint---~--------
for d in $WEBSITES_PATH* ; do
    dumpLog "Start backup $d"
    backupWebsite $d
done

