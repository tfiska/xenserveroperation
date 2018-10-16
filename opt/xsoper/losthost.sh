#!/bin/bash
# A host is hanging script for XenServer 6/6.02/6.1/6.2
# Run with hostname for hanging host as parameter
# Made by Trygve Gunnar Fiskaa, Evry
# Please ask me for help. :-)
# Mail/SIP: trygve.fiska@evry.com
# Phone: +47 41612477
XENHOSTNAME=$1
HOSTUUID=`xe host-list hostname=$XENHOSTNAME --minimal`
VMRESET=`xe vm-list resident-on=$HOSTUUID is-control-domain=false --minimal| tr "," "\n"`
DEBUG="TRUE" # Set to TRUE for debugging
echo "Listing and trying to force off affected VM's:"
for VMUUID in $VMRESET
do
	VMNAME=`xe vm-list uuid=$VMUUID params=name-label --minimal`
	xe vm-reset-powerstate uuid=$VMUUID --force
	echo "$VMNAME"

done

echo "Starting reset and reseting VDI for VM one by one..."
echo ""


for VMUUID in $VMRESET
do
	VMNAME=`xe vm-list uuid=$VMUUID params=name-label --minimal`
	VMSTATUS=`xe vm-list name-label=$VMNAME params=power-state --minimal`
	VMONHOSTUUID=`xe vm-list name-label=$VMNAME params=resident-on --minimal`
	TMPVMONHOSTUUID=$(echo $VMONHOSTUUID | sed 's/-//g' | sed 's/^/STR/')
	TMPHOSTUUID=$(echo $HOSTUUID|sed 's/-//g'|sed 's/^/STR/')
	if [ "$VMSTATUS" != "running" ] || [ "$TMPVMONHOSTUUID" == "$TMPHOSTUUID" ]; then
		if [ "$VMSTATUS" == "running" ]; then
			echo "Forcing off $VMNAME with status : $VMSTATUS :"
			xe vm-reset-powerstate uuid=$VMUUID --force
		else
			echo "$VMNAME is in status $VMSTATUS, skipping force off"
		fi
	else
		echo "VM already started on host:`xe host-list uuid=$VMONHOSTUUID params=name-label --minimal`"
	fi
	VBDUUIDS=`xe vm-disk-list vm=$VMNAME vbd-params=uuid vdi-params=none --minimal | tr "," " "` && if [ "$DEBUG" == "TRUE" ] ; then echo "VBDUUIDS : $VBDUUIDS" ;fi
	VMSTATUS=`xe vm-list name-label=$VMNAME params=power-state --minimal` && if [ "$DEBUG" == "TRUE" ] ; then echo "VMSTATUS : $VMSTATUS" ;fi

	if [ "$VMSTATUS" == "halted" ] ; then
			for VBDUUID in $VBDUUIDS
			do
					VDIUUID=`xe vbd-list uuid=$VBDUUID params=vdi-uuid --minimal` && if [ "$DEBUG" == "TRUE" ] ; then echo "VDIUUID : $VDIUUID" ;fi
					DEVICEID=`xe vbd-list uuid=$VBDUUID  params=userdevice --minimal` && if [ "$DEBUG" == "TRUE" ] ; then echo "DEVICEID : $DEVICEID" ;fi
					VMUUID=`xe vm-list name-label=$VMNAME --minimal` && if [ "$DEBUG" == "TRUE" ] ; then echo "VMUUID : $VMUUID" ;fi
					SRUUID=`xe vdi-list uuid=$VDIUUID params=sr-uuid --minimal` && if [ "$DEBUG" == "TRUE" ] ; then echo "SRUUID : $SRUUID" ;fi
					xe vdi-forget uuid=$VDIUUID
					xe sr-scan uuid=$SRUUID
					ADDDISK[$DEVICEID]="xe vbd-create vm-uuid=$VMUUID vdi-uuid=$VDIUUID device=$DEVICEID"  && if [ "$DEBUG" == "TRUE" ] ; then echo "ADDDISK[$DEVICEID] : ${ADDDISK[$DEVICEID]}" ;fi
			done
			VMDISKLIST=`xe vm-disk-list vm=$VMNAME` && if [ "$DEBUG" == "TRUE" ] ; then echo "VMDISKLIST : $VMDISKLIST" ;fi
			while [[  "$VMDISKLIST"  ]]
			do
					VMDISKLIST=`xe vm-disk-list vm=$VMNAME` && if [ "$DEBUG" == "TRUE" ] ; then echo "VMDISKLIST : $VMDISKLIST" ;fi
					sleep 2
			done
			for cmd in "${ADDDISK[@]}"
			do
					if [ "$DEBUG" == "TRUE" ] ; then echo "Running command: $cmd" ;fi
					$cmd
					sleep 2
			done
	else
			echo "The server $VMNAME are not in status halted, the status reported are $VMSTATUS"
	fi
	sleep 10
	xe vm-start  uuid=$VMUUID --force &
	#xe vm-list uuid=$VMUUID
done
