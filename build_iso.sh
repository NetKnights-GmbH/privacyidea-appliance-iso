#!/bin/bash
#
# Create a privacyIDEA Appliance installation iso-image.
# Based on a script by Leigh Purdie (<>)
#
# Required packages:
#     - apt-utils
#     - squashfs-tools
#     - gnupg
#     - devscripts
#     - rsync
#     - genisoimage
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
    echo "Usage: $0 [-h/-?] [-w <working directory>] [-b <base directory>] [-i <base iso-file>]";
    exit 1;
}

# The Base Directory
WORKDIR=$(mktemp -d)
# This directory will contain files that need to be copied over to the new CD.
EXTRASDIR=$(dirname $0)
# Ubuntu ISO image
CDIMAGE="ubuntu-16.04.4-server-amd64.iso"

verbose=0

while getopts $OPTIONS o; do
    case "${o}" in
        w)
            WORKDIR=${OPTARG}
            ;;
        b)
            EXTRASDIR=${OPTARG}
            ;;
	i)
	    CDIMAGE=${OPTARG}
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

if [ $verbose == 1 ]; then
    echo "Settings:";
    echo "   WORKDIR: $WORKDIR";
    echo "   EXTRASDIR: $EXTRASDIR";
    echo "   CDIMAGE: $CDIMAGE";
fi

exit 0

# file with extra package names
EXTRA_PKG_LIST=$EXTRASDIR/extra_packages.txt

# This directory contains extra packages
EXTRAPKGDIR="$WORKDIR/ExtraPackages"

# Seed file
SEEDFILE="privacyidea.seed"

# Ubuntu distribution
DIST="xenial"
ARCH=amd64

# Where the ubuntu iso image will be mounted
CDSOURCEDIR="$WORKDIR/cdsource"

# Directory for building packages
SOURCEDIR="$WORKDIR/source"

# GPG
GPGKEYNAME="PrivacyIDEA Installation Key"
GPGKEYCOMMENT="Package Signing"
GPGKEYEMAIL="packages@netknights.it"
GPGKEYPHRASE="MyLongButInsecurePassPhrase"
MYGPGKEY="$GPGKEYNAME ($GPGKEYCOMMENT) <$GPGKEYEMAIL>"
export GNUPGHOME="$WORKDIR/gnupg"

# Package list (dpkg -l) from an installed system.
PACKAGELIST="$SOURCEDIR/PackageList"

PNAME="privacyIDEA_Appliance"

# Output CD name
CDNAME="${PNAME}.iso"


# ------------ End of modifications.


################## Initial requirements
id | grep -c uid=0 >/dev/null
if [ $? -gt 0 ]; then
    echo "You need to be root in order to run this script.."
    echo " - sudo /bin/sh prior to executing."
    exit
fi

which gpg > /dev/null
if [ $? -eq 1 ]; then
    echo "Please install gpg to generate signing keys"
    exit
fi

# check if original cdimage exists
if [ ! -f $CDIMAGE ]; then
    echo "Cannot find your ubuntu image. Change CDIMAGE path."
    exit
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

# Check if a gpg-key already exists in the keyring, otherwise create it
gpg --list-keys | grep "$GPGKEYNAME" >/dev/null
if [ $? -ne 0 ]; then
    echo "No GPG Key found in your keyring."
    echo "Generating a new gpg key ($GPGKEYNAME $GPGKEYCOMMENT) with a passphrase of $GPGKEYPHRASE .."
    echo ""
    echo "Key-Type: RSA
Key-Length: 2048
Subkey-Type: ELG-E
Subkey-Length: 2048
Name-Real: $GPGKEYNAME
Name-Comment: $GPGKEYCOMMENT
Name-Email: $GPGKEYEMAIL
Expire-Date: 0
Passphrase: $GPGKEYPHRASE" > $WORKDIR/key.inc

    gpg --batch --gen-key $WORKDIR/key.inc
fi
# get the keyid of the key
MYGPGKEYID=$(gpg -k --with-colons "$GPGKEYNAME" | awk -F: '/^pub:/ {print substr($5, 9, 16)}')
if [[ -z $MYGPGKEYID ]]; then
    echo "Creation of GPG Key failed. Exiting."
    exit
fi

# mount the source cd image
if [ ! -f $CDSOURCEDIR/md5sum.txt ]; then
    echo -n "Mounting Ubuntu iso.. "
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

if [ ! -f $SOURCEDIR/apt.conf ]; then
    echo -n "No APT.CONF file found... generating one."
    # Try and generate one?
    cat $CDSOURCEDIR/dists/$DIST/Release | egrep -v "^( |Date|MD5Sum|SHA1|SHA256)" | sed 's/: / "/' | \
        sed 's/^/APT::FTPArchive::Release::/' | sed 's/$/";/' | sed 's/\(::Architectures\).*/\1 "amd64";/' | \
        sed 's/\(::Components ".*\)"/\1 extras"/' > $SOURCEDIR/apt.conf
    echo "Ok."
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

echo -n "Resyncing old data...  "

cd $WORKDIR/FinalCD
rsync -atz --delete $CDSOURCEDIR/ $WORKDIR/FinalCD/
echo "OK"


################## Remove packages that we no longer require

# PackageList is a dpkg -l from our 'build' server.
if [ ! -f $PACKAGELIST ]; then
    echo "No PackageList found. Assuming that you do not require any packages to be removed"
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
echo -n "Generating keyfile..   "

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

echo "Generating SquashFS..."

cd $SOURCEDIR/squashfs
rm -rf squashfs-root
unsquashfs $CDSOURCEDIR/install/filesystem.squashfs
# copy the generated keyring with our key to several locations
cp $KEYRING/keyrings/ubuntu-archive-keyring.gpg squashfs-root/usr/share/keyrings/ubuntu-archive-keyring.gpg
cp $KEYRING/keyrings/ubuntu-archive-keyring.gpg squashfs-root/etc/apt/trusted.gpg
cp $KEYRING/keyrings/ubuntu-archive-keyring.gpg squashfs-root/var/lib/apt/keyrings/ubuntu-archive-keyring.gpg
# get the new squashfs size
du -sx --block-size=1 squashfs-root/ | cut -f1 > $WORKDIR/FinalCD/install/filesystem.size
# create the new squashfs
rm -f $WORKDIR/FinalCD/install/filesystem.squashfs
mksquashfs squashfs-root $WORKDIR/FinalCD/install/filesystem.squashfs
# and sign it
rm -f $WORKDIR/FinalCD/install/filesystem.squashfs.gpg
gpg --batch --passphrase $GPGKEYPHRASE --output $WORKDIR/FinalCD/install/filesystem.squashfs.gpg -ab $WORKDIR/FinalCD/install/filesystem.squashfs

echo "OK"


################## Download/Update and copy the extra packages (if any)
if [[ -d $EXTRAPKGDIR ]]; then
    cd $EXTRAPKGDIR
    apt-get download $(cat $EXTRA_PKG_LIST)
    rsync -az --delete $EXTRAPKGDIR/ $WORKDIR/FinalCD/pool/extras/
fi

if [ -d $EXTRASDIR/ExtrasBuild ]; then
    echo -n "Copying Extra files...  "
    rsync -az $EXTRASDIR/ExtrasBuild/ $WORKDIR/FinalCD/

    if [ ! -f "$EXTRASDIR/ExtrasBuild/isolinux/isolinux.cfg" ]; then
        cat $CDSOURCEDIR/isolinux/isolinux.cfg | sed "s/^APPEND.*/APPEND   preseed\/file=\/cdrom\/preseed\/$SEEDFILE vga=normal initrd=\/install\/initrd.gz ramdisk_size=16384 root=\/dev\/rd\/0 DEBCONF_PRIORITY=critical debconf\/priority=critical rw --/" > $WORKDIR/FinalCD/isolinux/isolinux.cfg
    fi

    echo "OK"
fi


echo "Creating apt package list.."
cd $WORKDIR/FinalCD

apt-ftparchive -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-deb.conf
apt-ftparchive -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-udeb.conf
if [ -d $EXTRAPKGDIR ]; then
    EXRAS_DISTDIR="$WORKDIR/FinalCD/dists/$DIST/extras/binary-$ARCH"
    if [ ! -d $EXTRAS_DISTDIR ]; then
        mkdir -p $EXTRAS_DISTDIR
    fi
    if [ ! -f $EXTRAS_DISTDIR/Release ]; then
        cat $EXTRAS_DISTDIR/Release | sed 's/Component: main/Component: extras/' > $EXTRAS_DISTDIR/Release
    fi
    if [ ! -f $EXTRAS_DISTDIR/Packages ]; then
        apt-ftparchive -c $SOURCEDIR/apt.conf packages $WORKDIR/FinalCD/pool/extras $SOURCEDIR/indices/override.xenial.main > $EXTRAS_DISTDIR/Packages
    fi
    apt-ftparchive -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-extras.conf
fi


# Kill the existing release file
rm -f $WORKDIR/FinalCD/dists/$DIST/Release*

apt-ftparchive -c $SOURCEDIR/apt.conf release dists/$DIST/ > $WORKDIR/FinalCD/dists/$DIST/Release

echo "$GPGKEYPHRASE" | gpg --default-key "$MYGPGKEY" --passphrase-fd 0 --output $WORKDIR/FinalCD/dists/$DIST/Release.gpg -ba $WORKDIR/FinalCD/dists/$DIST/Release
echo "OK"

cd $WORKDIR/FinalCD
echo -n "Updating md5 checksums.. "
chmod 666 md5sum.txt
rm -f md5sum.txt
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
echo "OK"

cd $WORKDIR/FinalCD
echo "Creating and ISO image..."
mkisofs -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -hide-rr-moved -V $PNAME -o $WORKDIR/$CDNAME -R $WORKDIR/FinalCD/

echo "CD Available in $WORKDIR/$CDNAME"
echo "You can now remove all files in:"
echo " - $WORKDIR/FinalCD"

# Unmount the old CD
#umount $CDSOURCEDIR

