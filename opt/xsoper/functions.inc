

function cleanup {
# ------------------------------------------------------------------
#Cleanup part
# ------------------------------------------------------------------

#Temp for stream files Tommy Langengen 21.02.2014 : opplevde dette problemet på en xenserver igår https://issues.apache.org/jira/browse/CLOUDSTACK-1 Fix:
find /tmp -name "*stream*" -mtime +7 -exec rm -v {} \;
#From document "Free up disk space in Citrix XenServer", implemeted 11.05.14:
find /var/log -maxdepth 1 -name "*.gz" -type f -exec rm {} \;
find /tmp -maxdepth 1 -name "*.log" -type f -exec rm {} \;
find /var/tmp -maxdepth 1 -name "*.log" -type f -exec rm {} \;
}

function deamoncontrol {
# ------------------------------------------------------------------
#Deamon control
# ------------------------------------------------------------------
if [[ $SYSTEMCTLBIN == *":"* ]] ;then #check if SYSTEMCTL is not implemented
	if [ `service snmpd status |grep -c "stopped"` == 1 ]
	then
		#Start SNMPD and set to autostart
		service snmpd start
		chkconfig snmpd on
	fi
	#Update time
	service ntpd stop
	ntpd -gq  > /dev/null
	service ntpd start
else
	if [ $($SYSTEMCTLBIN status snmpd.service |grep -c "running") == 0 ]
	then
		$SYSTEMCTLBIN enable snmpd.service
		$SYSTEMCTLBIN start snmpd.service
	fi
	#Update time
	$SYSTEMCTLBIN stop ntpd.service
	ntpd -gq > /dev/null
	$SYSTEMCTLBIN start ntpd.service
fi
}


function poolcontrol {
  #**********************************************************************************| Pool part start |*********************************************************************************************************************************
  if grep master /etc/xensource/pool.conf 1> /dev/null
  then
  #***************************************************************************| This part of script runs only on Pool master |***********************************************************************************************************
  	#ID_RSA Part
  	IDRSA=$(xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=id_rsa)
  	IDRSAPUB=$(xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=id_rsa.pub)
  	if [ -z "$IDRSA" ] || [ -z "$IDRSAPUB" ]
  	then
  	  if ! [ -s /root/.ssh/id_rsa ] || ! [  -s /root/.ssh/id_rsa.pub ]
  	  then
  		ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -q -N ""
  	  fi
  	  IDRSAPUB=$(cat /root/.ssh/id_rsa.pub | tr "\n" ";" )
  	  xe pool-param-remove uuid=$POOLUUID param-name=other-config param-key=id_rsa.pub
  	  xe pool-param-set uuid=$POOLUUID other-config:id_rsa.pub="$IDRSAPUB"
  	  IDRSA=$(cat /root/.ssh/id_rsa|tr "\n" ";")
  	  xe pool-param-remove uuid=$POOLUUID param-name=other-config param-key=id_rsa
  	  xe pool-param-set uuid=$POOLUUID other-config:id_rsa="$IDRSA"
  	else
  	  if ! [ -s /root/.ssh/id_rsa ] || ! [  -s /root/.ssh/id_rsa.pub ]
  	  then
  		xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=id_rsa.pub | tr ";" "\n" > /root/.ssh/id_rsa.pub
  		xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=id_rsa| tr ";" "\n" > /root/.ssh/id_rsa
  		chmod 600 /root/.ssh/id_rsa
  	  fi


  	fi



  	#Clear old messages:
  	ENDMESSAGE="This is Pool Master!"
  	echo "Pool master detected, running pool part of script"
  	POOLCHECKOVERCOMMITUUID=`xe pool-list tags:contains=$CHECKOVERCOMMITTAG --minimal| tr "," ";"`
  	HOSTCHECKOVERCOMMITUUID=`xe host-list tags:contains=$CHECKOVERCOMMITTAG --minimal| tr "," ";"`
  	for msguuid in $(xe message-list obj-uuid=$POOLUUID name="Pool is Overcommited" --minimal|tr "," "\n"); do xe message-destroy uuid=$msguuid; done
  	for msguuid in $(xe message-list obj-uuid=$POOLUUID name="Singel server in pool" --minimal|tr "," "\n"); do xe message-destroy uuid=$msguuid; done
  	for msguuid in $(xe message-list obj-uuid=$POOLUUID name="Overcommited singel server" --minimal|tr "," "\n"); do xe message-destroy uuid=$msguuid; done
  	for msguuid in $(xe message-list obj-uuid=$POOLUUID name="To many vCPU's in use to allow mainatance" --minimal|tr "," "\n"); do xe message-destroy uuid=$msguuid; done
  	HOSTCOUNT=$(xe host-list params=name-label|grep -c "name-label")
  	VCPUUSEPOOL=$(xe vm-list power-state=running is-control-domain=false params=all| awk -F[\;:] '$0 ~ /VCPUs-number/ {sum += $2} END {print sum}')
  	POOLCPU=$(xe host-list params=cpu_info | awk -F[\;:] '$0 ~ /cpu_info/ {sum += $3} END {print sum}')
  	if [ $[$POOLCPU] -lt $[$VCPUUSEPOOL] ]; then
  		if [[ $POOLCHECKOVERCOMMITUUID == *"$POOLUUID"* ]]; then
  			if [ $[HOSTCOUNT] -eq 1 ];then
  				xe message-create body="Pool has singel server, and it is overcommited. There are $VCPUUSEPOOL vCPU's in use, and consists of $POOLCPU logical CPU's" name="Overcommited singel server" priority=2 pool-uuid=$POOLUUID
  			else
  				xe message-create body="Pool overcommited for CPU, please add more hosts or shutdown VM's (There are $VCPUUSEPOOL vCPU's in use in pool, and the pool consists of $POOLCPU logical CPU's)" name="Pool is Overcommited" priority=2 pool-uuid=$POOLUUID
  			fi
  		fi
  	elif [ $[$POOLCPU - ($POOLCPU / $HOSTCOUNT)] -lt $[$VCPUUSEPOOL] ]; then
  		if [ $[HOSTCOUNT] -eq 1 ];then
  			xe message-create body="Pool has singel server, this would not allow HA or mainatance, please consider adding more hosts to pool or you need to all shutdown vm's when running mainatance. There are $VCPUUSEPOOL vCPU's in use, and consists of $POOLCPU logical CPU's" name="Singel server in pool" priority=4 pool-uuid=$POOLUUID
  		else
  			if [[ $POOLCHECKOVERCOMMITUUID == *"$POOLUUID"* ]]; then xe message-create body="Pool has to many vcpus in use to allow HA or mainatance, please consider adding more hosts or you need to shutdown vm's or overcommit when running mainatance. There are $VCPUUSEPOOL vCPU's in use, and consists of $POOLCPU logical CPU's, there should be maximum $[$POOLCPU - ($POOLCPU / $HOSTCOUNT)] in use to allow maintanace and High Availabillity"  name="To many vCPU's in use to allow mainatance" priority=3 pool-uuid=$POOLUUID ; fi
  		fi
  		for CURRENTHOSTUUID in $(echo $HOSTLIST | tr "," "\n")
  		do
  			for msguuid in $(xe message-list obj-uuid=$CURRENTHOSTUUID name="Host is overcommited" --minimal|tr "," "\n"); do xe message-destroy uuid=$msguuid; done
  			CURRHOSTCPU=$(xe host-list params=cpu_info uuid=$CURRENTHOSTUUID| awk -F[\;:] '$0 ~ /cpu_info/ {sum += $3} END {print sum}')
  			CURRHOSTVCPUUSED=$(xe vm-list power-state=running is-control-domain=false  resident-on=$CURRENTHOSTUUID params=all| awk -F[\;:] '$0 ~ /VCPUs-number/ {sum += $2} END {print sum}')
  			if [ $[$CURRHOSTCPU] -lt $[$CURRHOSTVCPUUSED] ]
  			then
  				if [[ $POOLCHECKOVERCOMMITUUID == *"$POOLUUID"* ]] || [[ $HOSTCHECKOVERCOMMITUUID == *"$CURRENTHOSTUUID"* ]]; then xe message-create body="Host has overcommited CPU please consider moving vm's to other hosts. There are $CURRHOSTCPU logical CPU's on this host, and currently using $CURRHOSTVCPUUSED vCPUs, please migrate VM(s) with $[($CURRHOSTVCPUUSED - $CURRHOSTCPU)] vCPU's to an other host." name="Host is overcommited" priority=2 host-uuid=$CURRENTHOSTUUID ; fi
  			fi
  		done
  	else
  	for CURRENTHOSTUUID in $(echo $HOSTLIST | tr "," "\n")
  	do
  		for msguuid in $(xe message-list obj-uuid=$CURRENTHOSTUUID name="Host is overcommited" --minimal|tr "," "\n"); do xe message-destroy uuid=$msguuid; done
  		CURRHOSTCPU=$(xe host-list params=cpu_info uuid=$CURRENTHOSTUUID| awk -F[\;:] '$0 ~ /cpu_info/ {sum += $3} END {print sum}')
  		CURRHOSTVCPUUSED=$(xe vm-list power-state=running is-control-domain=false  resident-on=$CURRENTHOSTUUID params=all| awk -F[\;:] '$0 ~ /VCPUs-number/ {sum += $2} END {print sum}')
  		if [ $[$CURRHOSTCPU] -lt $[$CURRHOSTVCPUUSED] ]; then
  			if [[ $POOLCHECKOVERCOMMITUUID == *"$POOLUUID"* ]] || [[ $HOSTCHECKOVERCOMMITUUID == *"$CURRENTHOSTUUID"* ]]; then xe message-create body="Host has overcommited CPU please consider moving vm's to other hosts. There are $CURRHOSTCPU logical CPU's on this host, and currently using $CURRHOSTVCPUUSED vCPUs, please migrate VM(s) with $[($CURRHOSTVCPUUSED - $CURRHOSTCPU)] vCPU's to an other host." name="Host is overcommited" priority=2 host-uuid=$CURRENTHOSTUUID ; fi
  		fi

  	done
  	fi
  	#Check all VM's for CUST Tag
  	VMUUIDS=$(xe vm-list is-a-template=false is-a-snapshot=false is-control-domain=false --minimal)
  	for VMUUID in $(echo $VMUUIDS | tr "," "\n");do
  		VMTAGS=$(xe vm-list uuid=$VMUUID params=tags)
  		if [[ ! $VMTAGS = *"$CUSTOMERTAGPREFIX"* ]]; then
    			for msguuid in $(xe message-list obj-uuid=$VMUUID name="Server is missing $CUSTOMERTAGPREFIX TAG" --minimal | tr "," "\n");do xe message-destroy uuid=$msguuid;done
    			#echo "VM=$(xe vm-list uuid=$VMUUID params=name-label --minimal) TAGS=$VMTAGS"
     			if [ -n "$(xe pool-list params=tags|grep "Script-CustTag")" ];then xe message-create vm-uuid=$VMUUID name="Server is missing $CUSTOMERTAGPREFIX TAG" body="You should tag this vm with the $CUSTOMERTAGPREFIX[CUSTOMERNAME] tag for this Customer" priority=5;fi
  			xe vm-param-add uuid=$VMUUID param-name=tags param-key="$MISSINGCUSTOMERTAGNAME"
  		else
  			for msguuid in $(xe message-list obj-uuid=$VMUUID name="Server is missing $CUSTOMERTAGPREFIX TAG" --minimal | tr "," "\n");do xe message-destroy uuid=$msguuid;done
  			if [[ ! $VMTAGS != *"$MISSINGCUSTOMERTAGNAME"* ]]; then xe vm-param-remove uuid=$VMUUID param-name=tags param-key="$MISSINGCUSTOMERTAGNAME" ; fi
  		fi
  	done
  	#Disable all offloading, VIF & PIF
  	/root/scripts/offloadingoff.sh ALLSILENT >> $LOGDIR/$LOGFILE
  	echo "Offloading script disabled"
  	for PATCHUUID in $(xe patch-list --minimal | tr "," "\n")
  	do
  		HOSTMISSING=""
  		for CURRENTHOSTUUID in $(echo $HOSTLIST | tr "," "\n")
  		do
  			if [[ $(xe patch-list uuid=$PATCHUUID hosts:contains=$CURRENTHOSTUUID --minimal) != "$PATCHUUID" ]] ; then HOSTMISSING="$HOSTMISSING;$CURRENTHOSTUUID" ;fi
  		done
  		if [[ "$HOSTMISSING" == "" ]] ; then xe patch-pool-clean uuid=$PATCHUUID   ;fi
  	done
  	#Check if slaves have run script
  	HOSTDATEFORMAT="+%Y%m%dT%TZ"
  	NOWTIME=$(date $HOSTDATEFORMAT)

  	for uuid in $(xe host-list host-metrics-live=true params=uuid --minimal | tr "," "\n" )
  	do
  		MESSAGETIME=$(xe message-list name="Script Done" class=Host priority=5 params=timestamp --minimal obj-uuid=$uuid)
  		if [ -n "$MESSAGETIME" ]; then
  			DIFFTIME=$(echo "$(date -d "$(echo $NOWTIME | sed 's/.$//')" +%s) - $(date -d "$(echo $MESSAGETIME | sed 's/.$//')" +%s)" | bc)
  			if (( $DIFFTIME > 108000 ));
  			then
  				LASTMESSAGE="Please manual run maintanace script on this host, make sure this file exists \"/etc/cron.daily/updateEVRYstd.sh\""
  				xe message-create body="$LASTMESSAGE" name="Script missing schedule" priority=2 host-uuid=$uuid
  			else
  				echo "Script detected on $uuid"
  			fi
  		else
  			xe message-create body="$LASTMESSAGE" name="Script missing schedule" priority=2 host-uuid=$uuid
  		fi
  	done
  else
  #***************************************************************************| This part of script runs only on Pool slaves |***********************************************************************************************************
  	#If not pool master, we can clear patch folder
  	ENDMESSAGE="This host is slave of $POOLMASTERNAME!"
  	echo "Pool slave detected, running slave part of script"
  	sleep 10
  	if ! [ -s /root/.ssh/id_rsa ] || ! [  -s /root/.ssh/id_rsa.pub ]
  	then
  		xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=id_rsa.pub | tr ";" "\n" > /root/.ssh/id_rsa.pub
  		xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=id_rsa| tr ";" "\n" > /root/.ssh/id_rsa
  		chmod 600 /root/.ssh/id_rsa
  	fi
  	[ -d "/var/patch" ] && find /var/patch  -maxdepth 1 -type f -exec rm {} \;
  	[ -d "/var/update" ] && find /var/update  -maxdepth 1 -type f -exec rm {} \;
  fi
  #**********************************************************************************| Pool part ended |*********************************************************************************************************************************

}


function localhostcontrol{


  # ------------------------------------------------------------------
  #Local host settings
  # ------------------------------------------------------------------

  SEARCHDOMAIN=`cat /etc/resolv.conf |grep search|cut -d' ' -f2`;
  MGMTNICS=`xe pif-list host-uuid=$HOSTUUID management=true --minimal|tr "," "\n"`;
  LOCALNICS=`xe pif-list host-uuid=$HOSTUUID physical=true --minimal|tr "," "\n"`
  [ -z $SEARCHDOMAIN ] &&  SEARCHDOMAIN=`xe pif-list params=other-config --minimal|tr "," "\n"|grep domain|sort|uniq|head -n1|cut -d":" -f2| sed 's/^[ \t]*//;s/[ \t]*$//'`
  [ -z $SEARCHDOMAIN ] && echo "Search domain not found" || for PIFID in $MGMTNICS; do xe pif-param-set uuid=$PIFID other-config:domain=$SEARCHDOMAIN; done

  #Set PIF Domain name from pool:
  DNSDOM=`xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=domain 2> /dev/null`
  if [ -z "$DNSDOM" ]
  then
  	DNSDOM=`cat /etc/resolv.conf |grep search |awk '{print $2}'`
  	if [ ! -z "$DNSDOM" ]; then xe pool-param-set uuid=$POOLUUID other-config:domain=$DNSDOM ;fi
  fi

  if [ ! -z "$DNSDOM" ];then
  	PIFUUID=`xe pif-list host-uuid=$HOSTUUID VLAN=-1 device=bond0 params=all --minimal`
  	xe pif-param-set uuid=$PIFUUID other-config:domain=$DNSDOM
  	echo "search mgmt.local" > /tmp/resolv.conf
  	cat /etc/resolv.conf |grep -vi "SEARCH" >> /tmp/resolv.conf
  	rm -rf /etc/resolv.conf && mv /tmp/resolv.conf /etc
  fi

}

function xenversioncontrol{

  # ------------------------------------------------------------------
  #Version depended settings
  # ------------------------------------------------------------------
  if [[ "$XENVERSION" = "6.5.0" ]] ; then
  	echo "Xenserver 6.5.0 detected"
  	#On Xenserver 6.5
  	#only support MTU = 1500
  	for networkuuid in $(xe network-list MTU=9000 --minimal|tr ',' '\n') ; do xe network-param-set MTU=1500 uuid=$networkuuid; done
  elif [[ "$XENVERSION" = "7.1.0" ]] ; then
  	echo "Xenserver 7.1.0 detected"
  	#On Xenserver 7.1.0:
  	#No idetified version depended settings
  elif [[ "$XENVERSION" = "7.1.1" ]] ; then
  	echo "Xenserver 7.1.1 detected"
  	#On Xenserver 7.1.0:
  	#No idetified version depended settings
  fi

}

function sshsettings {
  # ------------------------------------------------------------------
  #SSH settings
  # ------------------------------------------------------------------
  [ ! -f /etc/ssh/ssh_host_rsa_key ] && dpkg-reconfigure openssh-server
  xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=id_rsa.pub | tr ";" "\n" >> /root/.ssh/authorized_keys
  cat /root/.ssh/authorized_keys | sort | uniq > /root/.ssh/authorized_keys.tmp &&  /bin/mv /root/.ssh/authorized_keys.tmp /root/.ssh/authorized_keys
  # ------------------------------------------------------------------
  #According to this article we set short hostname: http://support.citrix.com/article/CTX128918
  # ------------------------------------------------------------------
  xe host-set-hostname-live host-uuid=$HOSTUUID hostname=$SHORTHOSTNAME host-name=$SHORTHOSTNAME
  xe host-param-set uuid=$HOSTUUID name-label=$SHORTHOSTNAME

}

function fixiscsimp {
	for SRUUID in $(xe sr-list type=lvmoiscsi --minimal |tr "," "\n")
do
  for PBRUUID in $(xe pbd-list sr-uuid=$SRUUID host-name-label=$(hostname) --minimal | tr "," "\n")
  do
    PBDMULTIHOMELIST=$(xe pbd-param-get uuid=$PBRUUID param-name=device-config param-key=multihomelist --minimal |tr "," "\n" | cut -d: -f1 | tr "\n" ";"|sed "s/^\///;s/\;$//")
    PBDMULTIHOMECOUNT=$(echo $PBDMULTIHOMELIST |tr ";" "\n" | wc -l)
    CONNECTEDLIST=$(iscsiadm -m session | grep -Po '[0-9.]{7,15}'|tr "\n" ";")
    for iscsiip in $(echo $PBDMULTIHOMELIST |tr ";" "\n" )
    do
	  if [[ $CONNECTEDLIST != *$iscsiip* ]]
	  then
        iscsiadm -m node -T $(iscsiadm -m discovery --type sendtargets --portal $iscsiip | cut -f2 -d" ") -p $iscsiip -l
	  fi
    done
  done
done
}
