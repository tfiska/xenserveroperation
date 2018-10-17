#!/bin/bash
# ------------------------------------------------------------------
####  Title:
####  	autooperate.sh
####  Description:
####	Daily mantanace for Xenserver
####	for easy mainatance of Xenservers
####  Author :
####	Trygve Gunnar Fiskaa
####	
####	
####  
####	
####  Support for:
#### 	Xenserver 6.02
####	Xenserver 6.5
####	Xenserver 7.0
####	Xenserver 7.1
####	Xenserver 7.1.1
####	Xenserver 7.2
####
#### ------------------------------------------------------------------
####  Changelog:
####	2.0.0000	-	Beta version for GITHUB, changed from internal version
####
####
####
####
####
####
####
####
####
####
####
####
####
#### ------------------------------------------------------------------
VERSION="2.0.0000" #Script will check this and rerun if version is updated.
# ------------------------------------------------------------------
#Retriving variables
# ------------------------------------------------------------------
PROCSTARTED=`date`
SCRIPTNAME="${0##*/}"
LOGFILE=`echo "log_$SCRIPTNAME" | cut -f1 -d'.'`
SYSTEMCTLBIN=$(whereis systemctl 2>/dev/null | cut -d' ' -f2)

#Defining standard variables
PROXYFILE="/root/.proxy"
TMPDIR="/tmp"
LOGDIR="/var/log"
LOGHEADER="************** $SCRIPTNAME version $VERSION started $PROCSTARTED **************"
#Defining Other variables
FTPEXCLUDED="/patches,/install,/config,/poolstatus"
REMCRONTABFOLDER="crontab" #the folder to be synced (only name of the folder)
REMSCRIPTFOLDER="scripts"
LOCDUMPFOLDER="ftpdump" #Relative to TMP dir
LOCSCRIPTDIR="/root/scripts"
MULTIPATHFILE="/etc/multipath.conf"
MULTIPATHFILEURL="/config/multipath.conf"
DEFAULTNTPFILE="/etc/ntp.conf"
DEFAULTNTPURL="/config/ntp.conf"
SYSCONFIGFOLDER="/etc/sysconfig/"
SYSCONFIGFOLDERURL="/config/sysconfig/"
CHECKOVERCOMMITTAG="Script-ChceckOvercommit"
CUSTOMERTAGPREFIX="Cust-"
MISSINGCUSTOMERTAGNAME="_MISSING_CUST_TAG"
# ------------------------------------------------------------------
#Initiate Logging
# ------------------------------------------------------------------
[ -e $LOGDIR/$LOGFILE.7 ] && rm -rf $LOGDIR/$LOGFILE.7
[ -e $LOGDIR/$LOGFILE.6 ] && mv $LOGDIR/$LOGFILE.6 $LOGDIR/$LOGFILE.7
[ -e $LOGDIR/$LOGFILE.5 ] && mv $LOGDIR/$LOGFILE.5 $LOGDIR/$LOGFILE.6
[ -e $LOGDIR/$LOGFILE.4 ] && mv $LOGDIR/$LOGFILE.4 $LOGDIR/$LOGFILE.5
[ -e $LOGDIR/$LOGFILE.3 ] && mv $LOGDIR/$LOGFILE.3 $LOGDIR/$LOGFILE.4
[ -e $LOGDIR/$LOGFILE.2 ] && mv $LOGDIR/$LOGFILE.2 $LOGDIR/$LOGFILE.3
[ -e $LOGDIR/$LOGFILE.1 ] && mv $LOGDIR/$LOGFILE.1 $LOGDIR/$LOGFILE.2
[ -e $LOGDIR/$LOGFILE ] && mv $LOGDIR/$LOGFILE $LOGDIR/$LOGFILE.1
echo $LOGHEADER >> $LOGDIR/$LOGFILE 

# ------------------------------------------------------------------
#Initiate variables for localhost hostname and UUID
# ------------------------------------------------------------------
HOSTNAME=`hostname`
HOSTNAMEU=`hostname| tr '[:lower:]' '[:upper:]'` 
HOSTNAMEL=`hostname| tr '[:upper:]' '[:lower:]'` 
HOSTUUID=`xe host-list hostname=$HOSTNAME --minimal`
if [[ "$HOSTUUID" == "" ]] || [[ ${#HOSTUUID} -gt 36 ]]; then HOSTUUID=`xe host-list hostname=$HOSTNAME | grep "uuid ( RO)" | awk '{print $5}'` ; fi
if [[ "$HOSTUUID" == "" ]] || [[ ${#HOSTUUID} -gt 36 ]]; then HOSTUUID=`xe host-list name-label=$HOSTNAME --minimal` ; fi
if [[ "$HOSTUUID" == "" ]] || [[ ${#HOSTUUID} -gt 36 ]]; then HOSTUUID=`xe host-list name-label=$HOSTNAMEU --minimal` ; fi
if [[ "$HOSTUUID" == "" ]] || [[ ${#HOSTUUID} -gt 36 ]]; then HOSTUUID=`xe host-list name-label=$HOSTNAMEL --minimal` ; fi
if [[ "$HOSTUUID" == "" ]] || [[ ${#HOSTUUID} -gt 36 ]]; then HOSTUUID=`cat /etc/xensource-inventory |grep "INSTALLATION_UUID"|cut -d"'" -f2` ; fi
if [[ "$HOSTUUID" == "" ]] || [[ ${#HOSTUUID} -gt 36 ]]
then
	echo "Sorry, did not find your local host UUID, (-: Please contact Trygve for Bug fixing :-)"
	exit
fi

# ------------------------------------------------------------------
#Fix hostname to lowercase and remove any domainname (FQDN) from hostname.
# ------------------------------------------------------------------
XENHOSTNAME=$(xe host-list uuid=$HOSTUUID params=name-label --minimal | awk '{print tolower($0)}')
if [ "$HOSTNAME" != "$XENHOSTNAME" ] || [ "$HOSTNAME" == "localhost" ] ; then
	sysctl kernel.hostname=$XENHOSTNAME
	HOSTNAME=`hostname`
fi
SHORTHOSTNAME=`echo $HOSTNAME | cut -d'.' -f1 | tr '[:upper:]' '[:lower:]'` #Use standard lowercase hostname without FQDN


# ------------------------------------------------------------------
#Initiate variables for POOL
# ------------------------------------------------------------------
POOLMASTERUUID=`xe pool-list params=master --minimal`
POOLMASTERNAME=$(xe host-list uuid=$POOLMASTERUUID params=name-label --minimal)
POOLUUID=$(xe pool-list --minimal)
HOSTLIST=$(xe host-list --minimal)
HOSTISMASTER=`test "$POOLMASTERUUID" = "$HOSTUUID" && echo 1 || echo 0`
XENVERSION=`xe host-param-get uuid=$HOSTUUID param-name=software-version param-key=product_version --minimal`
NETWORKMODE=`cat /etc/xensource/network.conf`
FTPSERVERHOST=$(xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=FTPSERVERHOST) #recheving from pool
FTPSERVERUSER=$(xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=FTPSERVERUSER) #recheving from pool
FTPSERVERPASSWORD=$(xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=FTPSERVERPASSWORD) #recheving from pool
FTPSERVERMAINTFOLDER=$(xe pool-param-get uuid=$POOLUUID param-name=other-config param-key=FTPSERVERMAINTFOLDER) #recheving from pool
FTPSERVERURL="ftp://$FTPSERVERUSER:$FTPSERVERPASSWORD@$FTPSERVERHOST$FTPSERVERMAINTFOLDER"  #URL for the location of REMCRONTABFOLDER and REMSCRIPTFOLDER



# ------------------------------------------------------------------
#updating Special files
# ------------------------------------------------------------------
echo "Setting ntpd settings:" >> $LOGDIR/$LOGFILE 
wget -q -O $NTPFILE $NTPURL >> $LOGDIR/$LOGFILE 
echo "Setting multipath config :" >> $LOGDIR/$LOGFILE 
wget -q -O $MULTIPATHFILE $MULTIPATHFILEURL  >> $LOGDIR/$LOGFILE 
echo "Setting sysconfigs" >> $LOGDIR/$LOGFILE 
wget -q --no-cache --mirror -p -np -R index.html -X $FTPEXCLUDED --convert-links -P $SYSCONFIGFOLDER $SYSCONFIGFOLDERURL/ &> $LOGDIR/$LOGFILE.tmp && cat $LOGDIR/$LOGFILE.tmp >> $LOGDIR/$LOGFILE && /bin/rm $LOGDIR/$LOGFILE.tmp


# ------------------------------------------------------------------
#Cleanup part
# ------------------------------------------------------------------

#Temp for stream files Tommy Langengen 21.02.2014 : opplevde dette problemet på en xenserver igår https://issues.apache.org/jira/browse/CLOUDSTACK-1 Fix:
find /tmp -name "*stream*" -mtime +7 -exec rm -v {} \;
#From document "Free up disk space in Citrix XenServer", implemeted 11.05.14:
find /var/log -maxdepth 1 -name "*.gz" -type f -exec rm {} \;
find /tmp -maxdepth 1 -name "*.log" -type f -exec rm {} \;
find /var/tmp -maxdepth 1 -name "*.log" -type f -exec rm {} \;
# ------------------------------------------------------------------
#mirroring $FTPSERVERURL to $TMPDIR/$LOCDUMPFOLDER/
# ------------------------------------------------------------------
wget -q --no-cache --mirror -p -np -R index.html -X $FTPEXCLUDED --convert-links -P $TMPDIR/$LOCDUMPFOLDER $FTPSERVERURL/ &> $LOGDIR/$LOGFILE.tmp && cat $LOGDIR/$LOGFILE.tmp >> $LOGDIR/$LOGFILE && /bin/rm $LOGDIR/$LOGFILE.tmp
#Cleanup unnecessary files
find $TMPDIR/$LOCDUMPFOLDER/ -name '.listing' -exec /bin/rm -rf {} \; >> $LOGDIR/$LOGFILE 
find $TMPDIR/$LOCDUMPFOLDER/ -name '*.html' -exec /bin/rm -rf {} \; >> $LOGDIR/$LOGFILE 
find $TMPDIR/$LOCDUMPFOLDER/ -type f -exec chmod +x  {} \; >> $LOGDIR/$LOGFILE


# ------------------------------------------------------------------
#Update Crontab:
# ------------------------------------------------------------------
LOCTMPFTPDIR=`find $TMPDIR/$LOCDUMPFOLDER/ -name $REMCRONTABFOLDER  -exec dirname  {} \;`
LOCTMPREMCRONTABFOLDER="$LOCTMPFTPDIR/$REMCRONTABFOLDER"
/bin/cp -r $LOCTMPREMCRONTABFOLDER/* /etc/ >> $LOGDIR/$LOGFILE 

# ------------------------------------------------------------------
#Update Scripts folder
# ------------------------------------------------------------------
LOCTMPREMSCRIPTSFOLDER="$LOCTMPFTPDIR/$REMSCRIPTFOLDER"
find $TMPDIR/$LOCDUMPFOLDER/ -type f -exec chmod +x  {} \;>> $LOGDIR/$LOGFILE 
if [ ! -d "$LOCSCRIPTDIR" ]; then mkdir $LOCSCRIPTDIR ; fi
/bin/cp -r $LOCTMPREMSCRIPTSFOLDER/* $LOCSCRIPTDIR >> $LOGDIR/$LOGFILE 

# ------------------------------------------------------------------
#Check if script was updated. (rerun if it is)
# ------------------------------------------------------------------
DOWNLOADEDVERSION=$(cat ${0} |grep ^VERSION*|cut -d\" -f2)
if [ "$DOWNLOADEDVERSION" != "$VERSION" ] ;then
	echo "Detecded updated version $DOWNLOADEDVERSION is downloaded, $VERSION is running, restarting "
	echo ""
	${0}
	exit 0
else
	echo "Newest script detected, continuing"
fi

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

# ------------------------------------------------------------------
# Run Arne Thon's get-inventory.pl to update UCMDB
# ------------------------------------------------------------------
export TEMP=/tmp
perl /root/scripts/get-inventory.pl -i . -p -u transit > /tmp/get-inventory.log 2>&1



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

# ------------------------------------------------------------------
#Linking autostart on boot (current run level:
# ------------------------------------------------------------------
#Link this script to current run level
ln -sf ${0} /etc/rc$(runlevel | cut -f2 -d" ").d/S99zzEvryStd.sh

#Linking Autostart script to hourly cron job
ln -sf $LOCSCRIPTDIR/autostartvms.sh /etc/cron.hourly/autostartvms.sh
ln -sf $LOCSCRIPTDIR/xenserverraporting.sh /etc/cron.daily/xenserverraporting.sh

#Fix security rights on maintanace cronfile
chmod 644 /etc/cron.d/maintanace 
chown root:root /etc/cron.d/maintanace

#clening old files 
[ -e /etc/cron.weekly/xs-stats.sh ] && rm -rf /etc/cron.weekly/xs-stats.sh
[ -e /etc/cron.d/sanstat ] && rm -rf /etc/cron.d/sanstat
[ -e $TMPDIR/$LOCDUMPFOLDER ] && rm -rf $TMPDIR/$LOCDUMPFOLDER

#remove old messsage for script done:
for msguuid in $(xe message-list obj-uuid=$HOSTUUID name=Script\ Done --minimal|tr "," "\n"); do xe message-destroy uuid=$msguuid; done

#Make new message for script finished:
duration=$(( $(date -u  +%s ) - $(date -u -d"$PROCSTARTED"  +%s) ))

LASTMESSAGE="Daily maintenance script (updateEVRYstd version: $VERSION) has completed successfully, the script took $(($duration / 60)) minutes and $(($duration % 60)) seconds. $ENDMESSAGE"
xe message-create body="$LASTMESSAGE" name="Script Done" priority=5 host-uuid=$HOSTUUID
echo "$LASTMESSAGE" >> $LOGDIR/$LOGFILE && echo "$LASTMESSAGE"

#No lines should be added after this.

