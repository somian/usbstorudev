#!/bin/sh
#-# -*- dash -*-
#-# storage-automount.sh in /lib/udev/
#-# set it to executable (sudo chmod +x /lib/udev/storage-automount.sh):
#-# before emplacing this script, create a directory "/media/udevam"!


# We also have to work with:
#   DEVTYPE
#   ID_FS_USAGE=filesystem  # not existing for whole disk w/ partitions.
#   ID_DRIVE_THUMB (=1)
#   and DEVLINKS=/dev/disk/by-id/usb-SanDisk_Cruzer_U_4C530200470804122305-0:0 ...
#   and ID_PART_ENTRY_NUMBER (=[12345 ...])

# if a plugdev group exist, retrieve its GID and set it as owner of the mountpoint
plugdev_gid="$(grep plugdev /etc/group|cut -f3 -d:)"

# Aye, this is rather complex, but finding the log turns out to be PITA with many log files: which one??.
_LOG_=TEST-$(date '+h%Hm%M_')
_LOG_=${_LOG_:+${DEVNAME##*/}_}${_LOG_:-${DEVNAME##*/}}
_LOG_="${_LOG_}:fired_by_udev.log"

TMPDIR=${TMPDIR:+/}${TMPDIR:-"/tmp/"}
export TMPDIR _LOG_

PLACEHOLDER=${DEVLINKS#*" "}

dtst=$(date '+%R %x')
if [ -n $ID_FS_TYPE ]
   then
  # truncate existing log (will not happen much bec. of timestamp in filename).
    printf   >$TMPDIR${_LOG_} \
           '%-20s\nUsing your script on a %s (%s)\n  FS~TYPE=%s\n  FS~LABEL=%s\n  AKA:  %s\n' \
           "$dtst" "${ID_DRIVE_THUMB:+USB thumb drive}" \
           "$DEVNAME" "$ID_FS_TYPE" "${ID_FS_LABEL:-"no label"}" \
           "$PLACEHOLDER"
    rm -vf   >>$TMPDIR${_LOG_} "/media/udevam/uda_${DEVNAME##*/}.log"
    ln -vs   >>$TMPDIR${_LOG_} ${TMPDIR}/${_LOG_} "/media/udevam/uda_${DEVNAME##*/}.log"
else
    exit 1  # Just do not do anything.  exit value makes no difference AFAIK.
fi 
# set the mountpoint name according to partition or device name
mount_point=$ID_FS_LABEL
devdesigntn=""

if [ -n ""$DRYRUN ]; then
    dtst=$(date '+%R %x')
    printf "Testing your script on: DEVNAME=%s FSTYPE=%s FSLABEL=%s"  >$TMPDIR${_LOG_} \
               "$DEVNAME" "$ID_FS_TYPE" "$ID_FS_LABEL"
    else
        case ${DEVNAME:-NULL} in
            (NULL) exit ;;
            (/dev/bus/*) rm $TMPDIR${_LOG_}
                         exit ;; ## DEVNAME *can* look like this: /dev/bus/usb/004/040 
            ( * ) :  ${passed_devname:=$DEVNAME}
        esac
        export PARENT_SCRIPT=$0
fi



#-# !!! #-# We have to find out whether the disk (block) device has partitions or not and the udev rule cannot tell.
dmc ()
{
    PARTS=3
    log_file=$2
    Iw="/dev/${1##*/}"
    if [ -n ""$DRYRUN ]; then
        printf >>$TMPDIR${_LOG_} 'Testing device "%s" as "%s"\n\n' "$1" "${Iw}"
    fi
    if test "-b ${Iw}"; then 
        RPARTS=$(/sbin/partprobe -ds $Iw 2>&1 >>"$TMPDIR${_LOG_}"  |grep -q 'partitions 1')
        PARTS=$?
        if [ -z $RPARTS ] && [ $PARTS -eq 0 ]; then return 3; fi # This is success for "whole disk / no partitions".
    fi
    return $PARTS
}

mountmi () # mount the device on created mountpoint
{
 # TODO use a separate script for this purpose, with better future options for logging.

    VFAT_OPTS=',noatime,nodiratime,nosuid,nodev,flush" # ",flushoncommit' => bad option
 # positional params;
    dev_to_mount="${1#/dev/}"
    mount_point="$2"
    system=${3:-$ID_FS_TYPE}"

    log_file=$TMPDIR${_LOG_}

   case "${system:-NULLDETECTION}" in
     ( NULLDETECTION | swap) echo  >>"$log_file" "ID_FS_TYPE is INVALID. Will now remove mountpoint dir:"
                             >>"$log_file" rmdir -v $mount_point"
              return 1 ; fi
     ;;

     ( vfat )
            if test "-e $dev_to_mount"
               then

              mount ${DRYRUN:+"-s -v"} >>"$log_file" 2>&1 \
       -n -t vfat \
       -o "rw,user,uid=0$gid,umask=002,dmask=002,fmask=002$VFAT_OPTS" \
              "/dev/$dev_to_mount" "$mount_point"
             mount_srv=$?
             if [ $mount_srv == 0 ]
                then fsck.vfat -f -v -y "/dev/$dev_to_mount"
                     mount -s -v 2>&1 >>"$log_file" \
                         -t vfat \
                         -o "rw,user,uid=0$gid,umask=002,dmask=002,fmask=002$VFAT_OPTS" \
                       "/dev/$dev_to_mount" "$mount_point"
             fi
 
            else echo Cannot mount vfat system because device file $dev_to_mount does not exist. >>"$log_file" 
            fi

     ;;
     ( ext? )
            if test "-e $dev_to_mount"
               then
         
              mount ${DRYRUN:+"-s -n -v"} >>"$log_file" 2>&1 \
       -t $system \
       -o defaults,rw,user,exec,dev "/dev/$dev_to_mount" "$mount_point"
             mount_srv=$?
             if [ $mount_srv == 0 ]
                then fsck.e2fs >>"$log_file" 2>&1 -p -E discard -f "/dev/$dev_to_mount"
                     fsck_srval=$?
                  if [ $fsck_srval -le 1 ]
                     then  # really mount the clean filesysem
                     mount -s -v >>"$log_file" 2>&1 \
                       -t $system \
                       -o defaults,rw,user,exec,dev "/dev/$dev_to_mount" "$mount_point"
                  else printf >>"$log_file" 'Error unexpectedly occured in mounting %s on %s. Aborting.\n' \
                        "$dev_to_mount" "$mount_point" 
                  fi
                mount_srv=$?
             fi

              mount ${DRYRUN:+"-s -v"} >>"$log_file" 2>&1 \
               -t $system \
               -o defaults,rw,user,exec,dev "/dev/$dev_to_mount" "$mount_point"
                     mount_srv=$?
             return $mount_srv
            else echo Cannot mount $dev_to_mount because device file for it does not exist. >>"$log_file" 
            fi
     ;;
     ( * ) mount ${DRYRUN:+"-n -v -s"} 2>&1 >>"$log_file" \
       -t $system -o defaults "/dev/$dev_to_mount" "$mount_point"
     ;;

   esac
}

cleanup ()
{
  for WO in `ls -1d /media/udevam/IN_USE_*`
        do  # -------------------------------------------------------------------------
     if [ $WO = $1 ]
     then continue
     else
     _T=$(df -h --output=size,source,target -l "$WO" | tail -n +2 | awk '($2 =~ "/dev/disk/by-uuid/") && ($3 == "/") {print "EMPTY"}')
         if [ x"$_T" = "xEMPTY" ]
             then
           if rmdir "$WO"
              then printf 2>&1 >>"$log_file" '    cleanup() removed empty dir %s\n' $WO 
           fi
         fi
     fi
        done  # -----------------------------------------------------------------------
 # Also remove dangling symlinks to log files using this:
  find /media/udevam/ -maxdepth 1 -name '*.log' -type l -exec test ! -e {} \; -print |xargs rm 


}

case ${DEVNAME##*/}Z in
    (sd??Z ) # This is a partition and we can be sure we want to *try* to ´mount´.
            devdesigntn=${DEVNAME##*/}
            printf >>$TMPDIR${_LOG_} 'Using disk partition device %s [%s]\n  DEVTYPE is "%s"\n  FS_USAGE is "%s"\n' \
                ${DEVNAME} $devdesigntn "$DEVTYPE" "$ID_FS_USAGE"
          # TODO based on the device name seek a "parent" full disk device log file and delete it.
        ;;
      # This needs more testing.
    (sd?Z  ) # This is a disk and we would want to mount it only if there is no partition table but there is an FSTYPE.
              if [ -z $ID_FS_USAGE ]
               then
                printf  >>"$TMPDIR${_LOG_}"  \ 
                  'There are partitions on this disk.  Not mounting as whole-disk.'
                  exit
              # if [ -z ""${DRYRUN} ] ; then
              #   exit # There ARE partitions, so we do not want to mount the whole disk; or
              # fi
               else devdesigntn=${DEVNAME##*/}
                    mount_point="nopart_BLOCKDEV_${devdesigntn}"
                printf  >>"$TMPDIR${_LOG_}"  \ 
                  'There ARE NO PARTITIONS on this disk.  Attempt mounting %s as whole-disk with filesystem type %s on %s.' \
                       "$DEVNAME" "$FSTYPE" "$mount_point"

              fi
        ;;
    ( *      ) printf >>"$TMPDIR${_LOG_}" 'Failed in script [case $DEVNAME]. Exiting.' "$DEVNAME"
               exit

        ;;
esac


if [ -z $mount_point ]; then
    mount_point="PARTITION-MOUNT-${devdesigntn}"
fi


#----- *-* ----- #
# create the mountpoint directory in /media/udevam
#----- *-* ----- #

 fQPN="/media/udevam/IN_USE_$mount_point"
 printf >>"$TMPDIR${_LOG_}" 'full path to mount point dir: %s\n' "$fQPN"

 ${DRYRUN:+echo }mkdir 2>&1 >>"$TMPDIR${_LOG_}" -vp "$fQPN"
 if [ -d $fQPN ]
    then : ${DDSTP:=$(date -r $fQPN -R)}
           
    else printf          >>"$TMPDIR${_LOG_}" \
       'mkdir "%s" failed. This will be last logged message for this device event.\n' "$fQPN"
        exit
 fi 
 if [ -z $plugdev_gid ]; then
     gid=''
 else
     ${DRYRUN:+echo} chown 2>&1  >>"$TMPDIR${_LOG_}" root:plugdev $fQPN
     chown :plugdev "$TMPDIR${_LOG_}" &&
     chmod g+w      "$TMPDIR${_LOG_}"
     gid=",gid=$plugdev_gid"
 fi
#----- *-* ----- #
# mount the block device indicated by "DEVNAME" on mount point 
#----- *-* ----- #
 if mountmi "$DEVNAME" "$fQPN" "$ID_FS_TYPE"
     then
   :  # do something interesting here, like scan the mounted disk for music files.
      printf >>"$TMPDIR${_LOG_}" \
          'Successfully mounted filesystem on dev %s at directory %s.\n' "$DEVNAME" "$fQPN"
      printf >>"$TMPDIR${_LOG_}" \
          'Device %s has links %s\nEnd of log!\n'  $DEVNAME "$DEVLINKS"
      # call cleanup function to keep /media/udevam tidier. arg is what we do NOT touch.
      cleanup "$fQPN"

     else
      printf >>"$TMPDIR${_LOG_}"  'FAILURE: could not mount %s on %s.' "$mount_point"

 fi
## NOTA BENE ##
## Use PROGRAM in rules to formulate a basename for the device using a sophisticated program; pass this name as part
## of the environment seen by us (this script program) and also to the "on remove" program.

#--# Last modified: 28 Nov 2014
#--# Installed to Mint 22 Nov 2014

