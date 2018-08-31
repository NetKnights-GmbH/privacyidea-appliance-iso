#!/bin/bash

while ! systemctl is-active --quiet mysql; do
    sleep 1
done

# just install pi-appliance and privacyidea-apache2, hopefully everything else is already installed.
dpkg -i /root/*.deb

# and reset the to the original rc.local template
cat <<- EOF > $0
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

exit 0
EOF
