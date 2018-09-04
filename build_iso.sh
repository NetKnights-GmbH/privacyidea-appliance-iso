#!/bin/bash
#
# Create a privacyIDEA Appliance installation iso-image.
# Based on a script by Leigh Purdie (<>)
#
# TODO:
#     - update/upgrade external template machine to get new packages
#     - make workdir parameter non-optional
#     - use external config file
#     - make script filesystem-agnostic, remove any fixed paths, download all
#       necessary files/folders


##
## Config section
##


OPTIND=1
OPTIONS="h?vi:"

print_usage() {
    echo "Usage: $0 [-h/-?] [-i <base iso-file>] <working directory>";
    exit 1;
}

# This directory will contain files that need to be copied over to the new CD.
EXTRASDIR=$(readlink -f $(dirname $0))
# Ubuntu ISO image
CDIMAGE_NAME="ubuntu-16.04.5-server-amd64.iso"
CDIMAGE_URL="http://releases.ubuntu.com/xenial/ubuntu-16.04.5-server-amd64.iso"
CDIMAGE_SHA256="c94de1cc2e10160f325eb54638a5b5aa38f181d60ee33dae9578d96d932ee5f8"
verbose=0
TEMPLATE_SERVER="pi-template.office.netknights.it"


while getopts $OPTIONS o; do
    case "${o}" in
        i)
            CDIMAGE=$(readlink -f ${OPTARG})
            ;;
        h|\?)
            print_usage
            ;;
        v)
            # currently not implemented
            verbose=1
            ;;
        *)
            print_usage
            ;;
    esac
done

shift $(($OPTIND - 1));

WORKDIR=$1

if [[ -z $WORKDIR ]]; then
    echo "No working directory given!"
    print_usage
fi
WORKDIR=$(realpath $WORKDIR)

# extra packages required on the build system
REQUIRED_PACKAGES="devscripts genisoimage squashfs-tools"

# file with extra package names
EXTRA_PKG_LIST=$EXTRASDIR/extra_packages.txt

# Seed file
SEEDFILE="privacyidea_base.seed"

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

# ------------ End of modifications.

################## Initial requirements
if [[ $(id -u) != 0 ]]; then
    echo "Running as an unprivileged user!"
    echo "Please make sure that sudo and passwordless login to the template machine work!"
    echo ""
fi

# The Base Directory
if [[ ! -d $WORKDIR ]]; then
    mkdir -p $WORKDIR
fi

# redirect stderr to logfile
exec 2> $WORKDIR/build_stderr.log

# check status of required packages
for i in $REQUIRED_PACKAGES; do
    if [[ $(LANG=C apt-cache policy $i | awk '$1 ~ /Installed:/ {print  $2}') = "(none)" ]]; then
        echo "Required Package $i not installed! Installing... "
        apt-get -qq install $i
    fi
done

# check CD image
if [[ -z $CDIMAGE ]]; then
    CDIMAGE=$WORKDIR/$CDIMAGE_NAME
fi

# check if original cdimage exists
if [[ ! -f $CDIMAGE ]]; then
    echo "Cannot find your base ubuntu image. Trying to download it from ubuntu server... "
    cd $WORKDIR && wget -c $CDIMAGE_URL && CDIMAGE=$WORKDIR/$CDIMAGE_NAME
fi

# check the image checksum
#if ! echo "$CDIMAGE_SHA256 $CDIMAGE" | sha256sum -c > /dev/null; then
#    echo "Could not verify checksum of ubuntu image!"
#    exit 1
#fi

echo "Settings:";
echo "=========";
echo "   WORKDIR: $WORKDIR";
echo "   EXTRASDIR: $EXTRASDIR";
echo "   CDIMAGE: $CDIMAGE";
echo "     Create ISO for installing privacyIDEA Server together with Appliance."
echo "--------------------------------------------------------------------------"


# Where the ubuntu iso image will be mounted
CDSOURCEDIR="$WORKDIR/cdsource"

# Directory for building packages
SOURCEDIR="$WORKDIR/source"

export GNUPGHOME="$WORKDIR/gnupg"

# Create a few directories.
if [ ! -d $WORKDIR ]; then mkdir -p $WORKDIR; fi
if [ ! -d $WORKDIR/FinalCD ]; then mkdir -p $WORKDIR/FinalCD; fi
if [ ! -d $CDSOURCEDIR ]; then mkdir -p $CDSOURCEDIR; fi
if [ ! -d $SOURCEDIR ]; then mkdir -p $SOURCEDIR; fi
if [ ! -d $SOURCEDIR/keyring ]; then mkdir -p $SOURCEDIR/keyring; fi
if [ ! -d $SOURCEDIR/indices ]; then mkdir -p $SOURCEDIR/indices; fi
if [ ! -d $SOURCEDIR/squashfs ]; then mkdir -p $SOURCEDIR/squashfs; fi
if [ ! -d $SOURCEDIR/bootlogo ]; then mkdir -p $SOURCEDIR/bootlogo; fi
if [ ! -d $GNUPGHOME ]; then mkdir -p $GNUPGHOME; fi
chmod 700 $GNUPGHOME


################## Download packages on the template machine
ssh root@${TEMPLATE_SERVER} "mkdir -p /root/pool/extras && cd /root/pool/extras && 
dpkg --get-selections | awk '{print \$1}' | xargs apt-get download 2>/dev/null" &
gather_pid=$!

echo ""

################## GPG Setup

# add some gpg preferences
cat << 'EOF' > $GNUPGHOME/gpg.conf
personal-digest-preferences SHA512
cert-digest-algo SHA512
default-preference-list SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP Uncompressed
keyid-format long
EOF
chmod 600 $GNUPGHOME/gpg.conf

# Check if a gpg-key already exists in the keyring, otherwise create it
MYGPGKEYID=$(gpg -k --with-colons "$GPGKEYNAME" | awk -F: '/^pub:/ {print $5}')
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
    MYGPGKEYID=$(gpg -k --with-colons "$GPGKEYNAME" | awk -F: '/^pub:/ {print $5}')
else
    echo "GPG Key for \"$GPGKEYNAME\" with keyid \"$MYGPGKEYID\" found in keyring."
fi

# Check the NetKnights Release Key
NK_FPR=$( gpg --with-fingerprint --with-colons $EXTRASDIR/ExtrasBuild/scripts/NetKnights-Release.asc | awk -F ':' '$1 == "fpr" {print $10}')
if [[ $NK_FPR != "09404ABBEDB3586DEDE4AD2200F70D62AE250082" ]]; then
    echo "Could not verify fingerprint of NetKnights Release Key! Exiting"
    exit
fi


################## Mount the source CD image
echo ""
if [ ! -f $CDSOURCEDIR/md5sum.txt ]; then
    echo -n "Mounting Ubuntu iso... "
    mount | grep $CDSOURCEDIR
    if [ $? -eq 0 ]; then
        umount $CDSOURCEDIR
    fi

    sudo mount -o loop,ro $CDIMAGE $CDSOURCEDIR/
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
    cat <<- EOF > $SOURCEDIR/apt-ftparchive-deb.conf
Dir {
  ArchiveDir "$WORKDIR/FinalCD";
};

TreeDefault {
  Directory "pool";
};

BinDirectory "pool/main" {
  Packages "dists/$DIST/main/binary-$ARCH/Packages";
  BinOverride "$SOURCEDIR/indices/override.$DIST.main";
  ExtraOverride "$SOURCEDIR/indices/override.$DIST.extra.main";
};

Default {
  Packages {
    Extensions ".deb";
    Compress ". gzip";
  };
};

Contents {
  Compress "gzip";
};
EOF
fi

if [ ! -f $SOURCEDIR/apt-ftparchive-udeb.conf ]; then
    cat <<- EOF > $SOURCEDIR/apt-ftparchive-udeb.conf
Dir {
  ArchiveDir "$WORKDIR/FinalCD";
};

TreeDefault {
  Directory "pool";
};

BinDirectory "pool/main" {
  Packages "dists/$DIST/main/debian-installer/binary-$ARCH/Packages";
  BinOverride "$SOURCEDIR/indices/override.$DIST.main.debian-installer";
};

Default {
  Packages {
    Extensions ".udeb";
    Compress ". gzip";
  };
};

Contents {
  Compress "gzip";
};
EOF
fi

if [ ! -f $SOURCEDIR/apt-ftparchive-extras.conf ]; then
    cat <<-EOF > $SOURCEDIR/apt-ftparchive-extras.conf
Dir {
  ArchiveDir "$WORKDIR/FinalCD";
};

TreeDefault {
  Directory "pool";
};

BinDirectory "pool/extras" {
  Packages "dists/$DIST/extras/binary-$ARCH/Packages";
  ExtraOverride "$SOURCEDIR/indices/override.$DIST.extra.main";
};

Default {
  Packages {
    Extensions ".deb";
    Compress ". gzip";
  };
};

Contents {
  Compress "gzip";
};
EOF
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
rsync -rltz --chmod=u+w $CDSOURCEDIR/ $WORKDIR/FinalCD/
echo "OK"


################## Create the ubuntu keyring package
echo ""
echo -n "Generating keyfile...  "
cd $SOURCEDIR/keyring
KEYRING=`find $SOURCEDIR/keyring -maxdepth 1 -name "ubuntu-keyring*" -type d -print`
if [ -z "$KEYRING" ]; then
    # TODO: this throws some warnings about missing keys and running as root
    wget http://de.archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2012.05.19.tar.gz
    wget http://de.archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2012.05.19.dsc
    tar xzf ubuntu-keyring_2012.05.19.tar.gz
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
# TODO: - check if package content changed so we don't need to rebuild squashfs
#         unfortunately we already synced the source cd content, so we should check before...
#       - this whole process needs root so i wrapped the calls with sudo...

echo ""
echo -n "Generating SquashFS... "

cd $SOURCEDIR/squashfs
# check if we already have a rebuild squashfs
# get the current md5sum of the ubuntu-archive-keyring.gpg file
REBUILD_SQUASHFS=0
MD5SUM_KEYRING=$(md5sum $KEYRING/keyrings/ubuntu-archive-keyring.gpg | awk '{print $1}')
SQUASH_KEYRING_FILES="squashfs-root/usr/share/keyrings/ubuntu-archive-keyring.gpg squashfs-root/etc/apt/trusted.gpg squashfs-root/var/lib/apt/keyrings/ubuntu-archive-keyring.gpg"
for i in $SQUASH_KEYRING_FILES; do
    if [[ -f $i ]] && ! echo "$MD5SUM_KEYRING  $i" | md5sum -c --quiet - > /dev/null; then
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
    sudo rm -rf squashfs-root
    sudo unsquashfs $CDSOURCEDIR/install/filesystem.squashfs
    # copy the generated keyring with our key to several locations
    for i in $SQUASH_KEYRING_FILES; do
        sudo cp $KEYRING/keyrings/ubuntu-archive-keyring.gpg $i
    done
    # get the new squashfs size
    sudo du -sx --block-size=1 squashfs-root/ | cut -f1 > filesystem.size
    # get the filesystem manifest
    sudo chroot squashfs-root/ dpkg-query -W --showformat='${binary:Package}\t${Version}\n' > filesystem.manifest
    # create the new squashfs
    sudo mksquashfs squashfs-root filesystem.squashfs
    # and sign it
    gpg --batch --passphrase $GPGKEYPHRASE --output filesystem.squashfs.gpg -ab filesystem.squashfs

    echo "  Done"
fi

# We just assume here that all squashfs files are generated correctly
cp -a filesystem.* $WORKDIR/FinalCD/install/
echo "OK"

# wait for the package download on the template machine to complete
wait $gather_pid

################## Download/Update and copy the extra packages (if any)
echo ""
echo -n "Downloading extra packages... "
rsync -rtz --exclude ubuntu-keyring_* root@${TEMPLATE_SERVER}:/root/pool/extras/ $WORKDIR/FinalCD/pool/extras/
echo "OK"

if [ -d $EXTRASDIR/ExtrasBuild ]; then
    echo -n "Copying Extra files...  "
    rsync -az $EXTRASDIR/ExtrasBuild/ $WORKDIR/FinalCD/
    echo "OK"
fi

echo ""
echo -n "Creating apt package list... "
cd $WORKDIR/FinalCD

apt-ftparchive -qq -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-deb.conf
apt-ftparchive -qq -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-udeb.conf
#if [ -d $EXTRAPKGDIR ]; then
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
#fi

# Kill the existing release file...
rm -f $WORKDIR/FinalCD/dists/$DIST/Release*

# ... rebuild ...
apt-ftparchive -qq -c $SOURCEDIR/apt.conf release dists/$DIST/ > $WORKDIR/FinalCD/dists/$DIST/Release

# ... and sign.
gpg --batch --default-key "$MYGPGKEY" --passphrase $GPGKEYPHRASE --output $WORKDIR/FinalCD/dists/$DIST/Release.gpg -ba $WORKDIR/FinalCD/dists/$DIST/Release
echo "OK"


################## Update files on Image
# update disk info file
mydate=$(date +"%Y%m%d")
sed -i "s/^\(.*\) - \(.*\) ([0-9]\{8\})$/privacyIDEA Appliance (based on \1) - \2 ($mydate)/" $WORKDIR/FinalCD/.disk/info


################## Update boot logo
echo -n "Adding boot logo... "
cd $SOURCEDIR/bootlogo
cpio -i < $WORKDIR/FinalCD/isolinux/bootlogo
cp $EXTRASDIR/ExtrasBuild/isolinux/splash.pcx .
ls . | cpio -o > $WORKDIR/FinalCD/isolinux/bootlogo
echo "OK"


################## Finalize
cd $WORKDIR/FinalCD
echo -n "Updating md5 checksums... "
rm -f md5sum.txt
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
echo "OK"

cd $WORKDIR/FinalCD
echo -n "Creating ISO image... "
mkisofs -b isolinux/isolinux.bin -c isolinux/boot.cat -input-charset utf-8 \
        -quiet -no-emul-boot -boot-load-size 4 -boot-info-table -J -hide-rr-moved \
        -V $PNAME -o $WORKDIR/$CDNAME -R $WORKDIR/FinalCD/
if [[ $? != 0 ]]; then
    echo "Generating the ISO image failed!"
    exit 1
fi
echo "OK"
echo ""

# make the work directory available for non-root user (or copy the image somewhere else?)
chmod 755 $WORKDIR

echo "Finished"
echo "========"
echo "CD Available in $WORKDIR/$CDNAME"
echo "----------------------------------------------------------------------"

# Unmount the old CD image
sudo umount $CDSOURCEDIR

