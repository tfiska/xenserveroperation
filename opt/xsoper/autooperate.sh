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
source "/opt/xsoper/initiate.bsh"







# ------------------------------------------------------------------
# Run Arne Thon's get-inventory.pl to update UCMDB
# ------------------------------------------------------------------
export TEMP=/tmp
perl /root/scripts/get-inventory.pl -i . -p -u transit > /tmp/get-inventory.log 2>&1






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
