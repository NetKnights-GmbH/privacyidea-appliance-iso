#!/bin/bash

### mount cdrom
[[ ! -f /media/cdrom/md5sum ]] && mount /dev/sr0 /media/cdrom

### update sshd config to allow root login with pw
sed -i -e 's/\(^PermitRootLogin\).*$/\1 yes/' /etc/ssh/sshd_config

### install all requirements for privacyidea-apache2 and pi-appliance
LANG=C apt-cache depends privacyidea-apache2

PIAPACHE_DEPS=$(LANG=C apt-cache depends privacyidea-apache2 | grep 'Depends:' | awk 'BEGIN{a=0}{if($1 ~ /^\|Depends:/){a=1;print $2}else{if(a == 1){a = 0}else{print $2}}}')

PIAPPL_DEPS=$(LANG=C apt-cache depends pi-appliance | grep 'Depends:' | awk 'BEGIN{a=0}{if($1 ~ /^\|Depends:/){a=1;print $2}else{if(a == 1){a = 0}else{print $2}}}')

# remove the privacyidea-apache2 dependency from the list
PI_APPLIANCE_DEPS=$(for i in $PIAPPL_DEPS; do if [[ $i != "privacyidea-apache2" ]]; then echo $i;fi; done)

#echo "apt-get install -y $PIAPACHE_DEPS $PI_APPLIANCE_DEPS"
apt-get install -y $PIAPACHE_DEPS $PI_APPLIANCE_DEPS

PI_APACHE2_DEB=$(find /media/cdrom/pool -name privacyidea-apache2*.deb)
PI_APPLIANCE_DEB=$(find /media/cdrom/pool -name pi-appliance*.deb)
#echo "$PI_APACHE2_DEB, $PI_APPLIANCE_DEB"
cp $PI_APACHE2_DEB $PI_APPLIANCE_DEB /root/

# copy the firstboot script to /etc/rc.local
cp /media/cdrom/scripts/firstboot_script.sh /etc/rc.local
