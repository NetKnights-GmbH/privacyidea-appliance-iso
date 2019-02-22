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
PI_APPLIANCE_DEB=$(find /media/cdrom/pool -name pi-appliance*.deb)

#echo "apt-get install -y $PIAPACHE_DEPS $PI_APPLIANCE_DEPS"
apt-get install -y $PIAPACHE_DEPS $PI_APPLIANCE_DEPS

PI_APACHE2_DEB=$(find /media/cdrom/pool -name privacyidea-apache2*.deb)
cp $PI_APACHE2_DEB $PI_APPLIANCE_DEB /root/

### add the enterprise repository packet signing  key to the apt keyring
apt-key add /media/cdrom/scripts/NetKnights-Release.asc

# copy the firstboot script to /etc/rc.local
cp /media/cdrom/scripts/firstboot_script.sh /etc/rc.local

# update login banner
sed -i -e 's/^\(Ubuntu .*\) \\n.*$/privacyIDEA Appliance (based on \1) \\l\n\n'\
'Please go to https:\/\/\\4\/ for the privacyIDEA web frontend./' /etc/issue

# update lsb-release
sed -i -e 's/^\(DISTRIB_DESCRIPTION="\)\(.*\)"$/\1privacyIDEA (based on \2)"/' /etc/lsb-release

cat << "EOF" > /etc/update-motd.d/00-pi-header
#!/bin/sh
[ -r /etc/lsb-release ] && . /etc/lsb-release
if [ -z "$DISTRIB_DESCRIPTION" ] && [ -x /usr/bin/lsb_release ]; then
	# Fall back to using the very slow lsb_release utility
	DISTRIB_DESCRIPTION=$(lsb_release -s -d)
fi
PI_VERSION=$(dpkg-query -W -f='${Version}' python-privacyidea | awk -F- '{print $1}')
if echo $LANG | grep -Eq de_DE ; then
    printf "Wilkommen bei\n"
else
    printf "Welcome to\n"
fi
printf "             _                    _______  _______ \n"
printf "   ___  ____(_)  _____ _______ __/  _/ _ \\/ __/ _ |\n"
printf "  / _ \\/ __/ / |/ / _ \`/ __/ // // // // / _// __ |\n"
printf " / .__/_/ /_/|___/\\_,_/\\__/\\_, /___/____/___/_/ |_| v$PI_VERSION\n"
printf "/_/                       /___/\n"
printf "   %s (%s %s %s)\n" "$DISTRIB_DESCRIPTION" "$(uname -o)" "$(uname -r)" "$(uname -m)"
EOF

# and update the help text printed as motd
cat << "EOF" > /etc/update-motd.d/10-pi-help-text
#!/bin/sh
printf "\n"
if echo $LANG | grep -Eq de_DE ; then
    printf " * Dokumentation:  "
else
    printf " * Documentation:  "
fi
printf "https://privacyidea.readthedocs.io\n"
printf " * Forum:          https://community.privacyidea.org\n"
printf " * Support:        https://netknights.it/en/leistungen/service-level-agreements/\n\n"

PI_REPOS_LP="ppa.launchpad.net/privacyidea/privacyidea/"
PI_REPOS_EP="lancelot.netknights.it/apt/"
repos_configured=$(grep -Erh "^deb " /etc/apt/sources.list* | grep -E "($PI_REPOS_LP)|($PI_REPOS_EP)")
if [ -z "$repos_configured" ]; then
    if echo $LANG | grep -Eq de_DE ; then
        printf " Dies ist eine Testinstallation von privacyIDEA.\n"
        printf " Derzeit werden keine Updates installiert!\n"
        printf " Bei Interesses an kommerziellen Support und Updates für privacyIDEA wenden Sie sich an:\n"
    else
        printf " This is a test installation of privacyIDEA.\n"
        printf " Currently no updates will be installed!\n"
        printf " If You are interested in commercial support and updates of privacyIDEA please contact:\n"
    fi
    printf "    NetKnights GmbH\n    Phone: +49 561 3166797\n    Email: info@netknights.it\n"
    printf "    Web:   https://netknights.it/en/leistungen/support/\n\n"
fi
EOF
# deactivate initial motd header and help text
chmod 644 /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text
# and activate our own
chmod 755 /etc/update-motd.d/00-pi-header /etc/update-motd.d/10-pi-help-text

# The base image seems to do something different during an EFI installation
# to get the installed system to boot properly (into grub).
# After an installation with the modified image, one gets dropped into the
# EFI-Shell on every boot (in my case with kvm/qemu). Since the EFI boot entry
# couldn't be made persistent, we just drop in a workaround: an efi boot
# script with the correct boot loader.
[[ -d /boot/efi/ ]] && echo -e "echo -off\nfs0:\\\EFI\\\ubuntu\\\grubx64.efi" > /boot/efi/startup.nsh || true
