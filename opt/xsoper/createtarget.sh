#!/bin/bash
# Create Targets for XenServer 602/61
# 1. Tags SAN and Templates you want to choose with the $TEMPLATETAG tag
# 2. Run script and answer questions.
# Made by Trygve Gunnar Fiskaa, Evry
# Please ask me for help. :-)
# Mail/SIP: trygve.fiska@evry.com
# Phone: +47 41612477
POOLNAME=`xe pool-list params=name-label |  awk '{print $5}'`
TEMPLATETAG="Script-TargetDevice"
TEMPFILE="/tmp/vmlist.txt"
OUTFILE=""
SILENT="FALSE"
NUMBEROFTARGETS=1
NUMBERTARGETSTART=1
NUMBEROFDIGITS=2
SERVERPREFIX=""
COLLECTIONNAME="Collection"
SITENAME="Site"
#####################################################################################FUNCTIONS##############################################################################################################
function helpusage()
{
    echo "# -n and --nameprefix  have required arguments. (SERVERPREFIX)"
    echo "# -q  and --numberoftarget  have required arguments. (NUMBEROFTARGETS)"
    echo "# -i  and --presetnumber  have required arguments. (NUMBERTARGETSTART)"
    echo "# -d and --digitcount  have required arguments. (NUMBEROFDIGITS)"
    echo "# -p and --pvssite have required arguments. (SITENAME)"
    echo "# -c and --pvscollection have required arguments. (COLLECTIONNAME)"
    echo "# -s and --silent skip confirmation (SILENT)"
    echo "# -o and --outfile set to export pvsimport to file (OUTFILE)"
    echo "# -t and --temolatetag Set custom (TEMPLATETAG)"
    echo "# -h and --help"
}

function askfordata()
{
    OLD=""
    if [ "$SERVERPREFIX" != "" ] ; then
        OLD="$SERVERPREFIX"
    else
        OLD="EMPTY"
    fi
    read -p "Type prefix for the servers you want to create (Required) [$OLD]:" SERVERPREFIX
    if [ -z "$SERVERPREFIX" -a "$OLD" != "EMPTY" ] ; then SERVERPREFIX=$OLD ;fi
    if [ -z "$SERVERPREFIX" -a $SERVERPREFIX != " " ]
    then
        echo "Server Prefix required, script aborted"
        exit 1;
    fi
    if [ $NUMBEROFTARGETS != "" ] ; then OLD=$NUMBEROFTARGETS ; else OLD="EMPTY";   fi
    read -p "Type the number of targets you want to create [$OLD]:" NUMBEROFTARGETS
    if [ -z "$NUMBEROFTARGETS" -a "$NUMBEROFTARGETS" != " " ] ; then  if [ "$OLD" != "EMPTY" ] ; then NUMBEROFTARGETS=$OLD ;else NUMBEROFTARGETS=1 ;fi ;fi

    if [ $NUMBERTARGETSTART != "" ] ; then OLD=$NUMBERTARGETSTART ; else OLD="EMPTY";   fi
    read -p "Type vm # the start number [$OLD]:" NUMBERTARGETSTART
    if [ -z "$NUMBERTARGETSTART" -a "$NUMBERTARGETSTART" != " " ] ; then  if [ "$OLD" != "EMPTY" ] ; then NUMBERTARGETSTART=$OLD ;else NUMBERTARGETSTART=1 ;fi ;fi

    if [ $NUMBEROFDIGITS != "" ] ; then OLD=$NUMBEROFDIGITS ; else OLD="EMPTY"; fi
    read -p "type in number of digits [$OLD]:" NUMBEROFDIGITS
    if [ -z "$NUMBEROFDIGITS" -a "$NUMBEROFDIGITS" != " " ] ;   then  if [ "$OLD" != "EMPTY" ] ; then NUMBEROFDIGITS=$OLD ;else NUMBEROFDIGITS=2 ;fi ;fi

    if [ $SITENAME != "" ] ; then OLD=$SITENAME ; else OLD="EMPTY"; fi
    read -p "Enter PVS Site Name [$OLD]:" SITENAME
    if [ -z "$SITENAME" -a "$SITENAME" != " " ] ;   then  if [ "$OLD" != "EMPTY" ] ; then SITENAME=$OLD ;else SITENAME="Site" ;fi ;fi

    if [ $COLLECTIONNAME != "" ] ; then OLD=$COLLECTIONNAME ; else OLD="EMPTY"; fi
    read -p "Enter PVS Collection Name [$OLD]:" COLLECTIONNAME
    if [ -z "$COLLECTIONNAME" -a "$COLLECTIONNAME" != " " ] ;   then  if [ "$OLD" != "EMPTY" ] ; then COLLECTIONNAME=$OLD ;else COLLECTIONNAME="Collection" ;fi ;fi

}



function getfreesan()
{
	local SRTEMPLLISTC=`xe sr-list tags:contains=$TEMPLATETAG --minimal| tr "," ";"`
    local SRUUID2=""
    for SRUUID in $(echo $SRTEMPLLISTC|tr ";" "\n") #$SRTEMPLLIST
    do
        local SRTOTSIZE=`xe sr-list uuid=$SRUUID params=physical-size --minimal`
        local SRUSEDSIZE=`xe sr-list uuid=$SRUUID params=physical-utilisation --minimal`
        local SRFREESPACE=`echo "$SRTOTSIZE - $SRUSEDSIZE" |bc`
        if  [[ "$SRFREESPACE" -gt "$TEMPLDISKSIZE" ]]
        then
			if [[ "$SRUUID2" == "" ]] ; then
				SRUUID2=$SRUUID
			else
				#echo $SRUUID
				break
			fi
        fi
    done
	echo $SRUUID2
}

#####################################################################################/FUNCTIONS##############################################################################################################

if [ $(whoami) != 'root' ];
then
    echo "Must be root to run $0"
    exit 1;
fi

while getopts "hsn:q:i:d:p:c:o:t: --long usage,silent,nameprefix:,numberoftarget:,presetnumber:,digitcount:,pvssite:,pvscollection:,outfile:,temolatetag:" OPTION
do
    case $OPTION in
        h|usage)
            helpusage
            exit 1
            ;;
        s|silent)
            SILENT="TRUE"
            ;;
        n|nameprefix)
            SERVERPREFIX=$OPTARG
            ;;
        q|numberoftarget)
            NUMBEROFTARGETS=$OPTARG
            ;;
        i|presetnumber)
            NUMBERTARGETSTART=$OPTARG
            ;;
        d|digitcount)
            NUMBEROFDIGITS=$OPTARG
            ;;
        p|pvssite)
            SITENAME=$OPTARG
            ;;
        c|pvscollection)
            COLLECTIONNAME=$OPTARG
            ;;
        o|outfile)
            OUTFILE=$OPTARG
            ;;
        t|temolatetag)
            TEMPLATETAG=$OPTARG
            ;;
    esac
done


SRTEMPLLIST=`xe sr-list tags:contains=$TEMPLATETAG --minimal| tr "," ";"`
if [ -z "$SRTEMPLLIST" -a "$SRTEMPLLIST" != " " ]
then
    echo "No Storage devices detected, please tag the SR you want to use with the tag '$TEMPLATETAG' "
    exit 1
fi



CREATETEMPLATENAMES=`xe template-list tags:contains=$TEMPLATETAG params=name-label --minimal| tr "," ";"`

if [ -z "$CREATETEMPLATENAMES" -a "$CREATETEMPLATENAMES" != " " ]
then
    echo "No templates detected, please tag the templates with tag '$TEMPLATETAG' "
    exit 1
elif [ `echo $CREATETEMPLATENAMES |tr ";" "\n" |wc -l` == 1 ]
then
    CREATETEMPLATENAME="$CREATETEMPLATENAMES"
else
    PS3="Select template: "
    QUIT="Quit this"
    select TEMPLATE in `echo $CREATETEMPLATENAMES | tr ";" "\n"`; do
        CREATETEMPLATENAME=$TEMPLATE
        if [ $CREATETEMPLATENAME ]; then break;fi
    done
fi


TEMPLVBDUUID=`xe vbd-list vm-name-label=$CREATETEMPLATENAME type=Disk --minimal`
TEMPLDISKSIZE=`xe vdi-list vbd-uuids:contains=$TEMPLVBDUUID params=physical-utilisation --minimal`


if [ -z "$SERVERPREFIX" -a "$SERVERPREFIX" != " " ]
then
    askfordata
fi


if [ $SILENT != "TRUE" ] ; then
    echo "SERVERPREFIX                  = $SERVERPREFIX"
    echo "NUMBEROFTARGETS               = $NUMBEROFTARGETS"
    echo "NUMBERTARGETSTART             = $NUMBERTARGETSTART"
    echo "NUMBEROFDIGITS                = $NUMBEROFDIGITS"
    echo "SITENAME                      = $SITENAME"
    echo "COLLECTIONNAME                = $COLLECTIONNAME"
    echo "SILENT                        = $SILENT"
    echo "OUTFILE                       = $OUTFILE"
    echo "TEMPLATETAG                   = $TEMPLATETAG"



    read -p "E for edit, Enter ENTER to continue, any other to abort:" CONTINUE
    if [ -z "$CONTINUE" -a "$CONTINUE" != " " ]
    then
        echo "User choose to continue"
        SILENT="TRUE"
    elif [ "$CONTINUE" == "E" || "$CONTINUE" == "e" ]
    then
        echo "User choose to edit Settings"
    else
        echo "Script aborted, User aborted"
        exit 1
    fi
fi

#echo "Script aborted, DEBUG!!"
#exit 1;


rm -rf $TEMPFILE $> /dev/null
FORMAT=`echo "%0"$NUMBEROFDIGITS"d"`
for (( c=1; c<=$NUMBEROFTARGETS; c++ ))
do
  i=`echo "$c -1 + $NUMBERTARGETSTART" |bc`
  NUM=`printf "$FORMAT" $i`
  NEWNAME=$SERVERPREFIX$NUM
  SRUUID=`getfreesan | tr -d "[:space:]"` && echo "Detected free san uuid :\"$SRUUID\""
  #echo "xe vm-install template=$CREATETEMPLATENAME sr-uuid=$SRUUID new-name-label=$NEWNAME"
  SRNAME=`xe sr-list uuid=$SRUUID params=name-label --minimal`
  echo "Creating from $CREATETEMPLATENAME : $NEWNAME on $SRNAME"
  VMUUID=`xe vm-install template=$CREATETEMPLATENAME sr-uuid=$SRUUID new-name-label=$NEWNAME`
  xe vm-param-remove param-name=tags uuid=$VMUUID param-key=$TEMPLATETAG
  #xe vm-param-set uuid=${VMUUID} VCPUs-at-startup=${VCPU} && xe vm-param-set uuid=${VMUUID} xenstore-data:vm-data/ip=${IP} && xe vm-param-set uuid=${VMUUID} xenstore-data:vm-data/gw=${GW} && xe vm-param-set uuid=${VMUUID} xenstore-data:vm-data/nm=${MASK} && xe vm-param-set uuid=${VMUUID} xenstore-data:vm-data/ns=${DNS} && xe vm-param-set uuid=${VMUUID} xenstore-data:vm-data/dm=${DNSDOMAIN}
  MAC=`xe vif-list vm-uuid=$VMUUID device=0 params=MAC --minimal|  sed 's/\://g'`
  PLATFORM=`xe vm-param-get uuid=$VMUUID param-name=platform`
  PVSDESCRIPTION="POOL=$POOLNAME; VMUUID=$VMUUID; SRNAME=$SRNAME; MAC=$MAC; "
  echo "$NEWNAME,$MAC,$SITENAME,$COLLECTIONNAME,$PVSDESCRIPTION" >> $TEMPFILE

done
clear
echo "Put these lines into a text-file and import it on your provisioning server : "
echo "Format: VMNAME, MAC, SITENAME, COLLECTIONNAME, PVSDESCRIPTION"
cat $TEMPFILE
rm -rf $TEMPFILE

exit 1;
