#!/bin/bash
# Script for XenServer 6/6.02/6.1/6.2
# Run parameter from all members in pool
# Made by Trygve Gunnar Fiskaa, Evry
# Please ask me for help. :-)
# Mail/SIP: trygve.fiska@evry.com
# Phone: +47 41612477
DEBUG="FALSE" # Set to TRUE for debugging
REMOTEPASSWORD=$1 && if [ "$DEBUG" == "TRUE" ] ; then echo "REMOTEPASSWORD : $REMOTEPASSWORD" ;fi
REMOTECOMMAND=$2 && if [ "$DEBUG" == "TRUE" ] ; then echo "REMOTECOMMAND : $REMOTECOMMAND" ;fi
ALLINPOOL=`xe host-list params=name-label --minimal | tr "," " "` && if [ "$DEBUG" == "TRUE" ] ; then echo "ALLINPOOL : $ALLINPOOL" ;fi
HOSTNAME=`hostname | tr '[:upper:]' '[:lower:]'` && if [ "$DEBUG" == "TRUE" ] ; then echo "HOSTNAME : $HOSTNAME" ;fi


for POOLMEMBER in $ALLINPOOL
do
        if [ ! `echo $POOLMEMBER | tr '[:upper:]' '[:lower:]'` == "$HOSTNAME" ]
        then
                if [ "$DEBUG" == "TRUE" ] ; then echo "$POOLMEMBER";fi
                #
#				ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$POOLMEMBER exec "$REMOTECOMMAND"
				IPADRESS=`xe host-list name-label=$POOLMEMBER params=address --minimal`
				SHORTNAME=`echo root@$POOLMEMBER | cut -d'.' -f1 ` && if [ "$DEBUG" == "TRUE" ] ; then echo "SHORTNAME : $SHORTNAME" ;fi
				echo "root@$POOLMEMBER's password:"
/usr/bin/expect <<EOD
set timeout 120
spawn bash -c "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$IPADRESS"
expect "password:"
send "$REMOTEPASSWORD\r"
expect "$SHORTNAME"
send "$REMOTECOMMAND\n"
expect "$SHORTNAME"
send "exit\n"

EOD
        else
                if [ "$DEBUG" == "TRUE" ] ; then echo "Skipping $POOLMEMBER , local server";fi
        fi
done
