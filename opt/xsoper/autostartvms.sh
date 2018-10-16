#!/bin/bash
# Start all vm that is halted with TAG=$AUTOSTARTTAG for XenServer 6/6.02/6.1/6.2
# Run script
# Made by Trygve Gunnar Fiskaa, Evry
# Please ask me for help. :-)
# Mail/SIP: trygve.fiska@evry.com
# Phone: +47 41612477
AUTOSTARTTAG="ZZ_AUTO_STARTUP"		# VM's marked with this tag and is shut down would auto start every time script runs
MAX24HTAG="Script-MaxUp24H"			# VM's marked with this tag would be booted if not XenServer Tools and more uptime than specified
MAX24HTIME="25"						# Max number of hours for MAX24HTAG can be up before rebooted
HOSTDATEFORMAT="+%Y%m%dT%TZ"		# Date format for the "xe" interface
MPHR=60								# Minutes pr Hour
SPM=60								# Seconds Pr Minutes
HPD=24								# Hour pr day
NOWTIME=$(date $HOSTDATEFORMAT)
HOSTUUID=`xe host-list hostname=$HOSTNAME --minimal`
if [[ "$HOSTUUID" == "" ]]; then HOSTUUID=`xe host-list hostname=$HOSTNAME | grep "uuid ( RO)" | awk '{print $5}'` ; fi
if [[ "$HOSTUUID" == "" ]]; then HOSTUUID=`xe host-list name-label=$HOSTNAME --minimal` ; fi
if [[ "$HOSTUUID" == "" ]]; then HOSTUUID=`xe host-list name-label=$HOSTNAMEU --minimal` ; fi
if [[ "$HOSTUUID" == "" ]]; then HOSTUUID=`xe host-list name-label=$HOSTNAMEL --minimal` ; fi
if [[ "$HOSTUUID" == "" ]]; then HOSTUUID=$LOCALUUID ; fi
if [[ "$HOSTUUID" == "" ]]
then
	echo "Sorry, did not find your local host UUID, Please contact Trygve for Bug fixing"
	exit
fi
POOLMASTERUUID=`xe pool-list params=master --minimal`
HOSTISMASTER=`test "$POOLMASTERUUID" = "$HOSTUUID" && echo 1 || echo 0`

if [ "$HOSTISMASTER" == "0" ]
then
	echo "Host is not master, please run at Pool Master"
	exit 0
fi


if [ `xe vm-list power-state=halted tags:contains=$AUTOSTARTTAG --minimal| tr "," "\n"| wc -c` == "1" ]
then
	echo "No server with TAG:$AUTOSTARTTAG is in powerstate halted"
else
	echo "starting servers :"
	for VMUUID in `xe vm-list power-state=halted tags:contains=$AUTOSTARTTAG --minimal| tr "," "\n"`
	do
		VMNAME=`xe vm-list uuid=$VMUUID params=name-label --minimal`
		echo "Trying to start $VMNAME"
		xe vm-start uuid=$VMUUID
	done
fi

if [ `xe vm-list tags:contains=$MAX24HTAG --minimal| tr "," "\n"| wc -c` == "1" ]
then
	echo "No server with TAG:$MAX24HTAG found."
else
	echo "Check uptime on servers with TAG:$MAX24HTAG"
	for VMUUID in `xe vm-list tags:contains=$MAX24HTAG --minimal| tr "," "\n"`
	do
		VMNAME=`xe vm-list uuid=$VMUUID params=name-label --minimal`
		VMSTARTTIME=`xe vm-list uuid=$VMUUID params=start-time --minimal`
		OSVERSION=$(xe vm-list uuid=$VMUUID params=os-version --minimal)
		if [ "<not in database>" == "$OSVERSION" ]
		then
			echo no tools, reboot VM
		else
			echo "${VMNAME} has Tools Installed was started ${VMSTARTTIME}, os-version: $OSVERSION"
			echo
python - <<END
import datetime
from dateutil.relativedelta import relativedelta
start = datetime.datetime.strptime(VMSTARTTIME, '%Y-%m-%d %H:%M:%S')
ends = datetime.datetime.strptime(NOWTIME, '%Y-%m-%d %H:%M:%S')

END
		fi

	done
fi




exit 0
