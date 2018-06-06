#!/bin/bash
#
# Create a privacyIDEA Appliance installation iso-image.
# Based on a script by Leigh Purdie (<>)
#
# TODO:
#     - make script filesystem-agnostic, remove any fixed paths, download all
#       necessary files/folders


##
## Config section
##

OPTIND=1
OPTIONS="h?vw:b:i:"

print_usage() {
    echo "Usage: $0 [-h/-?] [-w <working directory>] [-e <extras directory>] [-i <base iso-file>]";
    exit 1;
}

# This directory will contain files that need to be copied over to the new CD.
EXTRASDIR=$(readlink -f $(dirname $0))
# Ubuntu ISO image
CDIMAGE_NAME="ubuntu-16.04.4-server-amd64.iso"
CDIMAGE_URL="http://releases.ubuntu.com/xenial/ubuntu-16.04.4-server-amd64.iso"
CDIMAGE=$CDIMAGE_NAME
verbose=0


while getopts $OPTIONS o; do
    case "${o}" in
        w)
            WORKDIR=$(readlink -f ${OPTARG})
            ;;
        b)
            EXTRASDIR=$(readlink -f ${OPTARG})
            ;;
	i)
	    CDIMAGE=$(readlink -f ${OPTARG})
	    ;;
	h|\?)
	    print_usage
	    ;;
	v)
	    verbose=1
	    ;;
        *)
            print_usage
            ;;
    esac
done

# extra packages required on the build system
REQUIRED_PACKAGES="apt-utils devscripts genisoimage"

# file with extra package names
EXTRA_PKG_LIST=$EXTRASDIR/extra_packages.txt
EXTRA_PKGS_APPL="pi-appliance python-flask-cache python-pymysql-sa python-pyjwt"

# Seed file
SEEDFILE="privacyidea.seed"

# Ubuntu distribution
DIST="xenial"
ARCH=amd64

# GPG
GPGKEYNAME="PrivacyIDEA Installation Key"
GPGKEYCOMMENT="Package Signing"
GPGKEYEMAIL="packages@netknights.it"
GPGKEYPHRASE="MyLongButInsecurePassPhrase"
MYGPGKEY="$GPGKEYNAME ($GPGKEYCOMMENT) <$GPGKEYEMAIL>"


PNAME="privacyIDEA_Appliance"

# Output CD name
CDNAME="${PNAME}.iso"

# install the appliance or just the server
INSTALL_APPLIANCE=true

# ------------ End of modifications.


################## Initial requirements
# TODO: Do we need root only for mounting/umounting the image?
id | grep -c uid=0 >/dev/null
if [ $? -gt 0 ]; then
    echo "You need to be root in order to run this script.."
    echo " - sudo /bin/sh prior to executing."
    exit
fi

# check status of required packages
for i in $REQUIRED_PACKAGES; do
    if [[ "$(LANG=C dpkg-query -W -f='${db:Status-Status}\n' $i)" = "not-installed" ]]; then
        echo "Required Package $i not installed! Installing... "
        apt-get install $i
    fi
done

# check status of apt sources
DEB_SRC_REGEXP="^deb-src .*/ubuntu/\? xenial main restricted$"
DEB_SRC_ENTRY="deb-src http://de.archive.ubuntu.com/ubuntu/ xenial main restricted"
DEB_INST_REGEXP="^deb .*/ubuntu/\? xenial main/debian-installer$"
DEB_INST_ENTRY="deb http://de.archive.ubuntu.com/ubuntu/ xenial main/debian-installer"
PI_APPL_REGEXP="^deb .*lancelot.netknights.it/apt\(/.*\)\?/stable xenial main$"
if ! grep -e "$DEB_SRC_REGEXP" /etc/apt/sources.list /etc/apt/sources.list.d/*.list > /dev/null; then
    echo "No deb-src entry found in apt sources. Adding \"$DEB_SRC_ENTRY\" to /etc/apt/sources.list ... "
    echo $DEB_SRC_ENTRY >> /etc/apt/sources.list
fi
if ! grep -e "$DEB_INST_REGEXP" /etc/apt/sources.list /etc/apt/sources.list.d/*.list > /dev/null; then
    echo "No debian installer entry found in apt sources. Adding \"$DEB_INST_ENTRY\" to /etc/apt/sources.list ... "
    echo $DEB_INST_ENTRY >> /etc/apt/sources.list
fi
if ! grep -e "$PI_APPL_REGEXP" /etc/apt/sources.list /etc/apt/sources.list.d/*.list > /dev/null; then
    echo "No privacyIDEA Appliance enterprise repository configured."
    echo "Adding the public community PPA. The final ISO will only install the privacyIDEA Server, not the Appliance!"
    add-apt-repository -y ppa:privacyidea/privacyidea > /dev/null 2>&1
    INSTALL_APPLIANCE=false
    EXTRA_PKGS_APPL=""
fi
apt-get update -qq

# check if gpg is installed
which gpg > /dev/null
if [ $? -eq 1 ]; then
    echo "Please install gpg to generate signing keys"
    exit
fi

# The Base Directory
if [[ -z $WORKDIR ]]; then
    WORKDIR=$(mktemp -d)
fi

echo "Settings:";
echo "=========";
echo "   WORKDIR: $WORKDIR";
echo "   EXTRASDIR: $EXTRASDIR";
echo "   CDIMAGE: $CDIMAGE";
if [[ $INSTALL_APPLIANCE = "true" ]]; then
    echo "     Create ISO for installing privacyIDEA Server together with Appliance."
else
    echo "     Create ISO for installing only privacyIDEA Server (without Appliance)."
fi
echo "----------------------------------------------------------------------"


# This directory contains extra packages
EXTRAPKGDIR="$WORKDIR/ExtraPackages"

# Where the ubuntu iso image will be mounted
CDSOURCEDIR="$WORKDIR/cdsource"

# Directory for building packages
SOURCEDIR="$WORKDIR/source"

export GNUPGHOME="$WORKDIR/gnupg"

# Package list (dpkg -l) from an installed system.
PACKAGELIST="$SOURCEDIR/PackageList"

# check if original cdimage exists
if [ ! -f $CDIMAGE ]; then
    echo "Cannot find your base ubuntu image. Trying to download it from ubuntu server... "
    cd $WORKDIR && wget -c $CDIMAGE_URL && CDIMAGE=$WORKDIR/$CDIMAGE_NAME
fi

# Create a few directories.
if [ ! -d $WORKDIR ]; then mkdir -p $WORKDIR; fi
if [ ! -d $WORKDIR/FinalCD ]; then mkdir -p $WORKDIR/FinalCD; fi
if [ ! -d $CDSOURCEDIR ]; then mkdir -p $CDSOURCEDIR; fi
if [ ! -d $SOURCEDIR ]; then mkdir -p $SOURCEDIR; fi
if [ ! -d $SOURCEDIR/keyring ]; then mkdir -p $SOURCEDIR/keyring; fi
if [ ! -d $SOURCEDIR/indices ]; then mkdir -p $SOURCEDIR/indices; fi
if [ ! -d $SOURCEDIR/ubuntu-meta ]; then mkdir -p $SOURCEDIR/ubuntu-meta; fi
if [ ! -d $SOURCEDIR/squashfs ]; then mkdir -p $SOURCEDIR/squashfs; fi
if [ ! -d $GNUPGHOME ]; then mkdir -p $GNUPGHOME; fi
chmod 700 $GNUPGHOME

# check if extra packages need to be installed
if [[ -f $EXTRA_PKG_LIST ]]; then
    [[ ! -d $EXTRAPKGDIR ]] && mkdir -p $EXTRAPKGDIR
fi

echo ""

################## GPG Setup

# add some gpg preferences
cat << 'EOF' > $GNUPGHOME/gpg.conf
personal-digest-preferences SHA512
cert-digest-algo SHA512
default-preference-list SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP Uncompressed
EOF
chmod 600 $GNUPGHOME/gpg.conf

# Check if a gpg-key already exists in the keyring, otherwise create it
MYGPGKEYID=$(gpg -k --with-colons "$GPGKEYNAME" | awk -F: '/^pub:/ {print substr($5, 9, 16)}')
if [[ -z $MYGPGKEYID ]]; then
    echo "No GPG Key found in your keyring."
    echo "Generating a new gpg key ($GPGKEYNAME $GPGKEYCOMMENT) with passphrase \"$GPGKEYPHRASE\" ..."
    echo ""
    cat <<- EOF > $WORKDIR/key.inc
	Key-Type: RSA
	Key-Length: 2048
	Subkey-Type: ELG-E
	Subkey-Length: 2048
	Name-Real: $GPGKEYNAME
	Name-Comment: $GPGKEYCOMMENT
	Name-Email: $GPGKEYEMAIL
	Expire-Date: 0
	Passphrase: $GPGKEYPHRASE
	EOF
    gpg --batch --gen-key $WORKDIR/key.inc
    MYGPGKEYID=$(gpg -k --with-colons "$GPGKEYNAME" | awk -F: '/^pub:/ {print substr($5, 9, 16)}')
else
    echo "GPG Key for \"$GPGKEYNAME\" with keyid \"$MYGPGKEYID\" found in keyring."
fi

################## Mount the source CD image
echo ""
if [ ! -f $CDSOURCEDIR/md5sum.txt ]; then
    echo -n "Mounting Ubuntu iso... "
    mount | grep $CDSOURCEDIR
    if [ $? -eq 0 ]; then
        umount $CDSOURCEDIR
    fi

    mount -o loop,ro $CDIMAGE $CDSOURCEDIR/
    if [ ! -f $CDSOURCEDIR/md5sum.txt ]; then
        echo "Mount did not succeed. Exiting."
        exit
    fi
    echo "OK"
fi

################## Setup APT configuration

if [ ! -f $SOURCEDIR/apt.conf ]; then
    echo ""
    echo -n "No APT.CONF file found. Generating one... "
    # Try and generate one?
    cat $CDSOURCEDIR/dists/$DIST/Release | egrep -v "^( |Date|MD5Sum|SHA1|SHA256)" | sed 's/: / "/' | \
        sed 's/^/APT::FTPArchive::Release::/' | sed 's/$/";/' | sed 's/\(::Architectures\).*/\1 "amd64";/' | \
        sed 's/\(::Components ".*\)"/\1 extras"/' > $SOURCEDIR/apt.conf
    echo "OK."
fi

if [ ! -f $SOURCEDIR/apt-ftparchive-deb.conf ]; then
    echo "Dir {
  ArchiveDir \"$WORKDIR/FinalCD\";
};

TreeDefault {
  Directory \"pool/\";
};

BinDirectory \"pool/main\" {
  Packages \"dists/$DIST/main/binary-$ARCH/Packages\";
  BinOverride \"$SOURCEDIR/indices/override.$DIST.main\";
  ExtraOverride \"$SOURCEDIR/indices/override.$DIST.extra.main\";
};

Default {
  Packages {
    Extensions \".deb\";
    Compress \". gzip\";
  };
};

Contents {
  Compress \"gzip\";
};" > $SOURCEDIR/apt-ftparchive-deb.conf
fi

if [ ! -f $SOURCEDIR/apt-ftparchive-udeb.conf ]; then
    echo "Dir {
  ArchiveDir \"$WORKDIR/FinalCD\";
};

TreeDefault {
  Directory \"pool/\";
};

BinDirectory \"pool/main\" {
  Packages \"dists/$DIST/main/debian-installer/binary-$ARCH/Packages\";
  BinOverride \"$SOURCEDIR/indices/override.$DIST.main.debian-installer\";
};

Default {
  Packages {
    Extensions \".udeb\";
    Compress \". gzip\";
  };
};

Contents {
  Compress \"gzip\";
};" > $SOURCEDIR/apt-ftparchive-udeb.conf
fi

if [ ! -f $SOURCEDIR/apt-ftparchive-extras.conf ]; then
    echo "Dir {
  ArchiveDir \"$WORKDIR/FinalCD\";
};

TreeDefault {
  Directory \"pool/\";
};

BinDirectory \"pool/extras\" {
  Packages \"dists/$DIST/extras/binary-$ARCH/Packages\";
  ExtraOverride \"$SOURCEDIR/indices/override.$DIST.extra.main\";
};

Default {
  Packages {
    Extensions \".deb\";
    Compress \". gzip\";
  };
};

Contents {
  Compress \"gzip\";
};" > $SOURCEDIR/apt-ftparchive-extras.conf
fi

if [ ! -f $SOURCEDIR/indices/override.$DIST.extra.main ]; then
    for i in override.$DIST.extra.main override.$DIST.main override.$DIST.main.debian-installer; do
        cd $SOURCEDIR/indices
        wget http://archive.ubuntu.com/ubuntu/indices/$i
    done
fi

################## Copy over the source data
echo ""
echo -n "Resyncing old data...  "

cd $WORKDIR/FinalCD
rsync -atz --delete $CDSOURCEDIR/ $WORKDIR/FinalCD/
echo "OK"


################## Remove packages that we no longer require

echo ""
# PackageList is a dpkg -l from our 'build' server.
if [ ! -f $PACKAGELIST ]; then
    echo "No PackageList found. Assuming that you do not require any packages to be removed."
else
    cat $PACKAGELIST | grep "^ii" | awk '{print $2 "_" $3}' > $SOURCEDIR/temppackages

    echo "Removing files that are no longer required.."
    cd $WORKDIR/FinalCD
    # Only use main for the moment. Keep all 'restricted' debs
    rm -f $SOURCEDIR/RemovePackages
    # Note: Leave the udeb's alone.
    for i in `find pool/main -type f -name "*.deb" -print`; do
        FILE=`basename $i | sed 's/_[a-zA-Z0-9\.]*$//'`
        GFILE=`echo $FILE | sed 's/\+/\\\+/g' | sed 's/\./\\\./g'`
        # pool/main/a/alien/alien_8.53_all.deb becomes alien_8.53
        egrep "^"$GFILE $SOURCEDIR/temppackages >/dev/null
        if [ $? -ne 0 ]; then
            # NOT Found
            # Note: Keep a couple of anciliary files

            zgrep "Filename: $i" $CDSOURCEDIR/dists/$DIST/main/debian-installer/binary-$ARCH/Packages.gz >/dev/null
            if [ $? -eq 0 ]; then
                # Keep the debian-installer files - we need them.
                echo "* Keeping special file $FILE"
            else
                echo "- Removing unneeded file $FILE"
                rm -f $WORKDIR/FinalCD/$i

            fi
        else
            echo "+ Retaining $FILE"
        fi
    done
fi

################## Create the ubuntu keyring package
echo ""
echo -n "Generating keyfile...  "
cd $SOURCEDIR/keyring
KEYRING=`find $SOURCEDIR/keyring -maxdepth 1 -name "ubuntu-keyring*" -type d -print`
if [ -z "$KEYRING" ]; then
    # TODO: should we run apt-get update before?
    # TODO: this throws some warnings about missing keys and running as root
    apt-get source ubuntu-keyring
    KEYRING=`find $SOURCEDIR/keyring -maxdepth 1 -name "ubuntu-keyring*" -type d -print`
    if [ -z "$KEYRING" ]; then
        echo "Cannot grab keyring source! Exiting."
        exit
    fi
fi

cd $KEYRING/keyrings
# TODO: this is a dirty hack to get the imported key ids
KEYIDS=$(LANG=C gpg --import < ubuntu-archive-keyring.gpg 2>&1 | awk '{if($2~"key"){gsub(/:$/, "",$3); print $3}}' | tr '\n' ' ')
# check if we already have a key
if [[ ! $KEYIDS =~ (^| )$MYGPGKEYID($| ) ]]; then
    rm -f ubuntu-archive-keyring.gpg
    gpg --output=ubuntu-archive-keyring.gpg --export $KEYIDS $MYGPGKEYID
    cd ..
    debuild -k"$MYGPGKEYID" -p"gpg --passphrase $GPGKEYPHRASE"
    rm -f $WORKDIR/FinalCD/pool/main/u/ubuntu-keyring/*
    cp ../ubuntu-keyring*deb $WORKDIR/FinalCD/pool/main/u/ubuntu-keyring/
    if [ $? -gt 0 ]; then
        echo "Cannot copy the modified ubuntu-keyring over to the pool/main folder. Exiting."
        exit
    fi
fi
echo "OK"


################## Update and rebuild squashfs
# TODO: check if package content changed so we don't need to rebuild squashfs
#       unfortunately we already synched the source cd content, so we should check before...
echo ""
echo -n "Generating SquashFS... "

cd $SOURCEDIR/squashfs
# check if we already have a rebuild squashfs
# get the current md5sum of the ubuntu-archive-keyring.gpg file
REBUILD_SQUASHFS=0
MD5SUM_KEYRING=$(md5sum $KEYRING/keyrings/ubuntu-archive-keyring.gpg | awk '{print $1}')
SQUASH_KEYRING_FILES="squashfs-root/usr/share/keyrings/ubuntu-archive-keyring.gpg squashfs-root/etc/apt/trusted.gpg squashfs-root/var/lib/apt/keyrings/ubuntu-archive-keyring.gpg"
for i in $SQUASH_KEYRING_FILES; do
    if [[ -f $i ]] && ! echo "$MD5SUM_KEYRING  $i" | md5sum -c --quiet - > /dev/null 2>&1; then
        REBUILD_SQUASHFS=1
        break
    fi
done

# check if all needed files are pressent
SQUASHFS_FILES="filesystem.squashfs filesystem.squashfs.gpg filesystem.size filesystem.manifest"
for i in $SQUASHFS_FILES; do
    if [[ ! -f $i ]]; then
        REBUILD_SQUASHFS=1
        break
    fi
done

if [[ $REBUILD_SQUASHFS == 1 ]]; then
    echo -n "  Need to rebuild squashfs... "
    rm -rf squashfs-root
    unsquashfs $CDSOURCEDIR/install/filesystem.squashfs
    # copy the generated keyring with our key to several locations
    for i in $SQUASH_KEYRING_FILES; do
        cp $KEYRING/keyrings/ubuntu-archive-keyring.gpg $i
    done
    # get the new squashfs size
    du -sx --block-size=1 squashfs-root/ | cut -f1 > filesystem.size
    # get the filesystem manifest
    chroot squashfs-root/ dpkg-query -W --showformat='${binary:Package}\t${Version}\n' > filesystem.manifest
    # create the new squashfs
    mksquashfs squashfs-root filesystem.squashfs
    # and sign it
    gpg --batch --passphrase $GPGKEYPHRASE --output filesystem.squashfs.gpg -ab filesystem.squashfs

    echo "  Done"
fi

# We just assume here that all squashfs files are generated correctly
cp -a filesystem.* $WORKDIR/FinalCD/install/
echo "OK"


################## Download/Update and copy the extra packages (if any)
echo ""
if [[ -f $EXTRA_PKG_LIST && -d $EXTRAPKGDIR ]]; then
    echo -n "Downloading extra packages... "
    cd $EXTRAPKGDIR
    apt-get download -qq $(cat $EXTRA_PKG_LIST) $EXTRA_PKGS_APPL
    rsync -az --delete $EXTRAPKGDIR/ $WORKDIR/FinalCD/pool/extras/
    echo "OK"
fi

if [ -d $EXTRASDIR/ExtrasBuild ]; then
    echo -n "Copying Extra files...  "
    rsync -az $EXTRASDIR/ExtrasBuild/ $WORKDIR/FinalCD/

    if [ ! -f "$EXTRASDIR/ExtrasBuild/isolinux/isolinux.cfg" ]; then
        cat $CDSOURCEDIR/isolinux/isolinux.cfg | sed "s/^APPEND.*/APPEND   preseed\/file=\/cdrom\/preseed\/$SEEDFILE vga=normal initrd=\/install\/initrd.gz ramdisk_size=16384 root=\/dev\/rd\/0 DEBCONF_PRIORITY=critical debconf\/priority=critical rw --/" > $WORKDIR/FinalCD/isolinux/isolinux.cfg
    fi
    echo "OK"
fi

echo ""
echo -n "Creating apt package list... "
cd $WORKDIR/FinalCD

apt-ftparchive -qq -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-deb.conf
apt-ftparchive -qq -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-udeb.conf
if [ -d $EXTRAPKGDIR ]; then
    EXTRAS_DISTDIR="$WORKDIR/FinalCD/dists/$DIST/extras/binary-$ARCH"
    if [ ! -d $EXTRAS_DISTDIR ]; then
        mkdir -p $EXTRAS_DISTDIR
    fi
    if [ ! -f $EXTRAS_DISTDIR/Release ]; then
        cat $WORKDIR/FinalCD/dists/$DIST/main/binary-$ARCH/Release | sed 's/Component: main/Component: extras/' > $EXTRAS_DISTDIR/Release
    fi
    if [ ! -f $EXTRAS_DISTDIR/Packages ]; then
        apt-ftparchive -qq -c $SOURCEDIR/apt.conf packages $WORKDIR/FinalCD/pool/extras $SOURCEDIR/indices/override.xenial.main > $EXTRAS_DISTDIR/Packages
    fi
    apt-ftparchive -qq -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-extras.conf
fi

# Kill the existing release file...
rm -f $WORKDIR/FinalCD/dists/$DIST/Release*

# ... rebuild ...
apt-ftparchive -qq -c $SOURCEDIR/apt.conf release dists/$DIST/ > $WORKDIR/FinalCD/dists/$DIST/Release

# ... and sign.
gpg --batch --default-key "$MYGPGKEY" --passphrase $GPGKEYPHRASE --output $WORKDIR/FinalCD/dists/$DIST/Release.gpg -ba $WORKDIR/FinalCD/dists/$DIST/Release
echo "OK"

################## Update files on Image
# TODO: update preeseed and final_script in case only server is installed
if [[ $INSTALL_APPLIANCE = "true" ]]; then
    echo "Updating preseed and script file"
    sed -i -e 's/^\(d-i[[:space:]]\+pkgsel\/include.*\)$/\1, aptitude, tinc/' $WORKDIR/FinalCD/preseed/$SEEDFILE
    sed -i -e 's/^INSTALL_APPLIANCE=false$/INSTALL_APPLIANCE=true/' $WORKDIR/FinalCD/scripts/final_script.sh
fi

# update disk info file
mydate=$(date +"%Y%m%d")
sed -i "s/^\(.*\) - \(.*\) ([0-9]\{8\})$/privacyIDEA Appliance (based on \1) - \2 ($mydate)/" $WORKDIR/FinalCD/.disk/info

cd $WORKDIR/FinalCD
echo -n "Updating md5 checksums.. "
chmod 666 md5sum.txt
rm -f md5sum.txt
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
echo "OK"

cd $WORKDIR/FinalCD
echo -n "Creating ISO image... "
mkisofs -b isolinux/isolinux.bin -c isolinux/boot.cat -input-charset utf-8 -quiet -no-emul-boot -boot-load-size 4 -boot-info-table -J -hide-rr-moved -V $PNAME -o $WORKDIR/$CDNAME -R $WORKDIR/FinalCD/
echo "OK"
echo ""

# make the work directory available for non-root user (or copy the image somewhere else?)
chmod 755 $WORKDIR

echo "Finished"
echo "========"
echo "CD Available in $WORKDIR/$CDNAME"
echo "----------------------------------------------------------------------"

# Unmount the old CD
umount $CDSOURCEDIR

