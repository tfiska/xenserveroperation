#!/bin/bash
# Bootscript
#
# Made by Trygve Gunnar Fiskaa, Evry
# Please ask me for help. :-)
# Mail/SIP: trygve.fiska@evry.com
# Phone: +47 41612477
#Getting locals
SCRIPTNAME="${0##*/}"
PROCSTARTED=`date`
HOSTNAME=`hostname`
POOLMASTERUUID=`xe pool-list params=master --minimal`

#Defining standard variables
TMPDIR="/tmp"


#Defining Other variables

#Check pool master
if ! grep master /etc/xensource/pool.conf 1> /dev/null; then
	echo "Please run on pool master to boot all the slaves"
	exit 1;
fi
POOLMASTERNAME=`xe host-list uuid=$POOLMASTERUUID params=name-label --minimal`

OTHERHOSTSUUIDS=`xe host-list --minimal|sed "s/"$POOLMASTERUUID"//g"|sed "s/,,/,/g"|tr "," "\n"`
OTERHOSTNAMES=` xe host-list params=name-label  --minimal|sed "s/"$POOLMASTERNAME"//g"|sed "s/,,/,/g"|tr "," "\n"|sort`
for TARGETHOSTNAME in $OTERHOSTNAMES
do
	HOSTUUID=`xe host-list name-label=$TARGETHOSTNAME --minimal`
	#TARGETHOSTNAME=`xe host-list uuid=$HOSTUUID params=name-label --minimal`
	xe host-disable host=$TARGETHOSTNAME
	echo "Rebooting : $TARGETHOSTNAME (UUID=$HOSTUUID)"
	NUMBVMONHOST=`xe vm-list resident-on=$HOSTUUID --minimal|sed -e 's/,/\n,/g' |grep -c ","`
	while [[ $NUMBVMONHOST != 0 ]]
	do
		echo "Trying Evacuate $NUMBVMONHOST vm's left on $TARGETHOSTNAME"
		xe host-evacuate host=$TARGETHOSTNAME
		sleep 5
		NUMBVMONHOST=`xe vm-list resident-on=$HOSTUUID  --minimal|sed -e 's/,/\n,/g' |grep -c ","`
	done
	xe host-reboot host=$TARGETHOSTNAME
	date
	HOSTINACTIVE=`xe host-list host-metrics-live=false uuid=$HOSTUUID |grep -c "$HOSTUUID"`
	while [[ $HOSTINACTIVE != 1 ]]
	do
		HOSTINACTIVE=`xe host-list host-metrics-live=false uuid=$HOSTUUID |grep -c "$HOSTUUID"`
		sleep 5
	done
	while [[ $HOSTINACTIVE != 0 ]]
	do
		HOSTINACTIVE=`xe host-list host-metrics-live=false uuid=$HOSTUUID |grep -c "$HOSTUUID"`
		sleep 5
	done
	xe host-enable host=$TARGETHOSTNAME
	HOSTDISABLED=`xe host-list enabled=false uuid=$HOSTUUID |grep -c "$HOSTUUID"`
	echo "Waiting for $TARGETHOSTNAME to become enabled"
	while [[ $HOSTDISABLED != 0 ]]
	do
		HOSTDISABLED=`xe host-list enabled=false uuid=$HOSTUUID |grep -c "$HOSTUUID"`
		sleep 5
	done
	VMGOINGHOME=`xe vm-list affinity=$HOSTUUID is-control-domain=false live=true --minimal | tr "," "\n"`
	for VMUUID in $VMGOINGHOME
	do
		printf "Moving \"`xe vm-list uuid=$VMUUID params=name-label --minimal`\" to it's home server :...."
		xe vm-migrate uuid=$VMUUID host-uuid=$HOSTUUID
		printf "done\n"
	done
done
xe host-evacuate host=$POOLMASTERUUID
sleep 30
HOSTUUID=$POOLMASTERUUID
VMGOINGHOME=`xe vm-list affinity=$HOSTUUID is-control-domain=false live=true --minimal | tr "," "\n"`
for VMUUID in $VMGOINGHOME
do
	printf "Moving \"`xe vm-list uuid=$VMUUID params=name-label --minimal`\" to it's home server :...."
	xe vm-migrate uuid=$VMUUID host-uuid=$HOSTUUID
	printf "done\n"
done
