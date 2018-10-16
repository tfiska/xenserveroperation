#!/bin/bash
# Fix networks for XenServer 602/61
#
#
# Made by Trygve Gunnar Fiskaa, Evry
# Please ask me for help. :-)
# Mail/SIP: trygve.fiska@evry.com
# Phone: +47 41612477
FQDNNAME=$(hostname -f 2>/dev/null)
if [ $? = 1 ] ; then FQDNNAME=$(hostname) ; fi
echo "Hostname (FQDN) : $FQDNNAME"


if [ -e "/usr/sbin/lldptool" ]
then
	echo "lldptool detected, enabling interfaces"
	for interface in `ls /sys/class/net/ | grep eth` ;
      do
		printf "%s\n" "$interface"
		ethtool $interface | grep -q 'Link detected: yes' || {
			echo "  down"
			echo
			continue
		}
		if [[ `lldptool get-lldp -i $interface adminStatus |grep disabled ` ]]
		then
		lldptool set-lldp -i "$interface" adminStatus=rxtx
			for item in sysName portDesc sysDesc sysCap mngAddr; do
				lldptool set-tlv -i "$interface" -V "$item" enableTx=yes |
				sed -e "s/^/$item /"
			done
			echo "enabled LLDP, waiting 10 seconds to receive data"
			sleep 10
		fi
		lldptool get-tlv -n -i "$interface" | sed -e "s/^/  /" | grep -A1 "Port\ Description\ TLV\|System\ Name\ TLV\|Management Address TLV"
		echo
	done
else
	for interface in `ls /sys/class/net/ | grep eth` ; do
		printf "%s\n" "$interface"
		ethtool $interface | grep -q 'Link detected: yes' || {
			echo "  down"
			echo
			continue
		}

		 IFINFO=$(tcpdump -v -s 1500 -c 1 '(ether[12:2]=0x88cc or ether[20:2]=0x2000)' -i $interface  2>&1 |grep "PVID\|Subtype\ Local\|System\ Name\|IPv4"| awk 'BEGIN { FS = ":" } ; {print $2}'| tr "\n" ";" |sed 's/.$//')
		 if  [[ $IFINFO == *"27 bytes"*  ]] ; then
			IFINFO=$(tcpdump -v -s 1500 -c 1 '(ether[12:2]=0x88cc or ether[20:2]=0x2000)' -i $interface  2>&1 |grep "PVID\|Subtype\ Local\|System\ Name\|IPv4"| awk 'BEGIN { FS = ":" } ; {print $2}'| tr "\n" ";" |sed 's/.$//')
		 fi
		 echo "---"
		 echo "Interface   : $interface"
		 echo "Switch name :$(echo $IFINFO | awk 'BEGIN { FS = ";" } ; {print $3}')"
		 echo "Switch IP   :$(echo $IFINFO | awk 'BEGIN { FS = ";" } ; {print $4}')"
		 echo "Port name   :$(echo $IFINFO | awk 'BEGIN { FS = ";" } ; {print $2}')"
		 echo "Native VLAN :$(echo $IFINFO | awk 'BEGIN { FS = ";" } ; {print $5}')"
	done
fi
