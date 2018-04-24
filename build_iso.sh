#
# Script by Leigh Purdie
#
# 1) Install a Ubuntu system, and remove packages according to your
#    requirements using synaptic.
#    Don't install any new packages that are NOT available from the CD,
#    at this stage, unless you include the packages in an 'extras' directory.
#
# 2) dpkg -l > PackageList
#    Copy this file to $BASEDIR/source on your build server.

# The Base Directory
BASEDIR="/data/MyBuildInstall"

# This directory will contain files that need to be copied over
# to the new CD.
EXTRASDIR="$BASEDIR/MyBuild"
# Seed file
SEEDFILE="privacyidea.seed"

# Ubuntu ISO image
CDIMAGE="$BASEDIR/ubuntu-16.04.4-server-amd64.iso"

# Ubuntu distribution
DIST="xenial"

# Where the ubuntu iso image will be mounted
CDSOURCEDIR="$BASEDIR/cdsource"

# Directory for building packages
SOURCEDIR="$BASEDIR/source"

# GPG
GPGKEYNAME="PivacyIDEA Installation Key"
GPGKEYCOMMENT="Package Signing"
GPGKEYEMAIL="packages@netknights.it"
GPGKEYPHRASE="MyOrg"
MYGPGKEY="$GPGKEYNAME ($GPGKEYCOMMENT) <$GPGKEYEMAIL>"
export GNUPGHOME="$BASEDIR/gnupg"

# Package list (dpkg -l) from an installed system.
PACKAGELIST="$SOURCEDIR/PackageList"

# Output CD name
CDNAME="MyBuild.iso"

# 640x480 PNG with colours as specified in
# https://wiki.ubuntu.com/USplashCustomizationHowto
#USPLASH="$SOURCEDIR/MyBuildSplash1.png"

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

# Create a few directories.
if [ ! -d $BASEDIR ]; then mkdir -p $BASEDIR; fi
if [ ! -d $BASEDIR/FinalCD ]; then mkdir -p $BASEDIR/FinalCD; fi
if [ ! -z $EXTRASDIR ]; then
        if [ ! -d $EXTRASDIR ]; then mkdir -p $EXTRASDIR; fi
        if [ ! -d $EXTRASDIR/preseed ]; then mkdir -p $EXTRASDIR/preseed; fi
        if [ ! -d $EXTRASDIR/pool/extras ]; then mkdir -p $EXTRASDIR/pool/extras; fi
fi
if [ ! -d $CDSOURCEDIR ]; then mkdir -p $CDSOURCEDIR; fi
if [ ! -d $SOURCEDIR ]; then mkdir -p $SOURCEDIR; fi
if [ ! -d $SOURCEDIR/keyring ]; then mkdir -p $SOURCEDIR/keyring; fi
if [ ! -d $SOURCEDIR/indices ]; then mkdir -p $SOURCEDIR/indices; fi
if [ ! -d $SOURCEDIR/ubuntu-meta ]; then mkdir -p $SOURCEDIR/ubuntu-meta; fi
if [ ! -d $GNUPGHOME ]; then mkdir -p $GNUPGHOME; fi
chmod 700 $GNUPGHOME

if [ ! -f $CDIMAGE ]; then
        echo "Cannot find your ubuntu image. Change CDIMAGE path."
        exit
fi


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
Passphrase: $GPGKEYPHRASE" > $BASEDIR/key.inc

        gpg --gen-key --batch --gen-key $BASEDIR/key.inc
        # Note: If you wish to remove the passphrase from the key:
        # (Don't do this if you want to use this key for ANYTHING other
        # than a temporary ubuntu CD installation signing key)
        # gpg --edit-key
        # passwd
        # (enter old phrase)
        # (blank)
        # (blank)
        # y
        # quit
        # y
fi

if [ ! -f $CDSOURCEDIR/md5sum.txt ]; then
        echo -n "Mounting Ubuntu iso.. "
        mount | grep $CDSOURCEDIR
        if [ $? -eq 0 ]; then
                umount $CDSOURCEDIR
        fi

        mount -o loop $CDIMAGE $CDSOURCEDIR/
        if [ ! -f $CDSOURCEDIR/md5sum.txt ]; then
                echo "Mount did not succeed. Exiting."
                exit
        fi
        echo "OK"
fi

if [ ! -f $SOURCEDIR/apt.conf ]; then
        echo -n "No APT.CONF file found... generating one."
        # Try and generate one?
        cat $CDSOURCEDIR/dists/$DIST/Release | egrep -v "^ " | egrep -v "^(Date|MD5Sum|SHA1)" | sed 's/: / "/' | sed 's/^/APT::FTPArchive::Release::/' | sed 's/$/";/' > $SOURCEDIR/apt.conf
        echo "Ok."
fi

if [ ! -f $SOURCEDIR/apt-ftparchive-deb.conf ]; then
        echo "Dir {
  ArchiveDir \"$BASEDIR/FinalCD\";
};

TreeDefault {
  Directory \"pool/\";
};

BinDirectory \"pool/main\" {
  Packages \"dists/$DIST/main/binary-i386/Packages\";
  BinOverride \"$SOURCEDIR/indices/override.$DIST.main\";
  ExtraOverride \"$SOURCEDIR/indices/override.$DIST.extra2.main\";
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
  ArchiveDir \"$BASEDIR/FinalCD\";
};

TreeDefault {
  Directory \"pool/\";
};

BinDirectory \"pool/main\" {
  Packages \"dists/$DIST/main/debian-installer/binary-i386/Packages\";
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
  ArchiveDir \"$BASEDIR/FinalCD\";
};

TreeDefault {
  Directory \"pool/\";
};

BinDirectory \"pool/extras\" {
  Packages \"dists/$DIST/extras/binary-i386/Packages\";
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

# Create a 'fixed' version of the extras.main override package.
# Idea/Perl by Ferry Hendrikx, 2006
cat $SOURCEDIR/indices/override.$DIST.extra.main | egrep -v ' Task ' > $SOURCEDIR/indices/override.$DIST.extra2.main
cat $CDSOURCEDIR/dists/$DIST/main/binary-i386/Packages | perl -e 'while (<>) { chomp; if(/^Package\:\s*(.+)$/) { $pkg=$1; } elsif(/^Task\:\s(.+)$/) { print "$pkg\tTask\t$1\n"; } }' >> $SOURCEDIR/indices/override.$DIST.extra2.main


################## Copy over the source data

echo -n "Resyncing old data...  "

cd $BASEDIR/FinalCD
rsync -atz --delete $CDSOURCEDIR/ $BASEDIR/FinalCD/
echo "OK"


################## Remove packages that we no longer require

# PackageList is a dpkg -l from our 'build' server.
if [ ! -f $PACKAGELIST ]; then
        echo "No PackageList found. Assuming that you do not require any packages to be removed"
else
        cat $PACKAGELIST | grep "^ii" | awk '{print $2 "_" $3}' > $SOURCEDIR/temppackages

        echo "Removing files that are no longer required.."
        cd $BASEDIR/FinalCD
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

                        grep "Filename: $i" $CDSOURCEDIR/dists/$DIST/main/debian-installer/binary-i386/Packages >/dev/null
                        if [ $? -eq 0 ]; then
                                # Keep the debian-installer files - we need them.
                                echo "* Keeping special file $FILE"
                        else
                                echo "- Removing unneeded file $FILE"
                                rm -f $BASEDIR/FinalCD/$i

                        fi
                else
                        echo "+ Retaining $FILE"
                fi
        done
fi


echo -n "Generating keyfile..   "

cd $SOURCEDIR/keyring
KEYRING=`find * -maxdepth 1 -name "ubuntu-keyring*" -type d -print`
if [ -z "$KEYRING" ]; then
        apt-get source ubuntu-keyring
        KEYRING=`find * -maxdepth 1 -name "ubuntu-keyring*" -type d -print`
        if [ -z "$KEYRING" ]; then
                echo "Cannot grab keyring source! Exiting."
                exit
        fi
fi

cd $SOURCEDIR/keyring/$KEYRING/keyrings
gpg --import < ubuntu-archive-keyring.gpg >/dev/null
rm -f ubuntu-archive-keyring.gpg
gpg --output=ubuntu-archive-keyring.gpg --export FBB75451 437D05B5 "$GPGKEYNAME" >/dev/null
cd ..
dpkg-buildpackage -rfakeroot -m"$MYGPGKEY" -k"$MYGPGKEY" >/dev/null
rm -f $BASEDIR/FinalCD/pool/main/u/ubuntu-keyring/*
cp ../ubuntu-keyring*deb $BASEDIR/FinalCD/pool/main/u/ubuntu-keyring/
if [ $? -gt 0 ]; then
        echo "Cannot copy the modified ubuntu-keyring over to the pool/main folder. Exiting."
        exit
fi

echo "OK"


################## Copy over the extra packages (if any)
if [ ! -z $EXTRASDIR ]; then
        echo -n "Copying Extra files...  "
        rsync -az $EXTRASDIR/ $BASEDIR/FinalCD/
        echo "OK"

        if [ ! -f "$EXTRASDIR/preseed/$SEEDFILE" ]; then
                echo "No seed file found. Creating one in $EXTRASDIR/preseed/$SEEDFILE."
                echo "- You will probably want to modify this file."
                echo "base-config  base-config/package-selection      string ~tubuntu-minimal|~tubuntu-desktop" > $EXTRASDIR/preseed/$SEEDFILE
        fi

        if [ -f $PACKAGELIST ]; then
                echo "Replacing ubuntu-desktop with a pruned package list.. "
                cd $SOURCEDIR/ubuntu-meta
                rm -rf ubuntu-*
                apt-get source ubuntu-meta
                META=`find * -maxdepth 1 -name "ubuntu-meta*" -type d -print`
                if [ -z "$META" ]; then
                      echo "Cannot grab source to ubuntu-meta. Exiting."
                      exit
                fi

                cd $META
                for i in `ls desktop*`; do
                        grep "^ii" $PACKAGELIST | awk '{print $2}' > $i.tmp
                        mv $i.tmp $i
                done

                dpkg-buildpackage -rfakeroot -m"$MYGPGKEY" -k"$MYGPGKEY" >/dev/null
                cd ..
                rm -f $BASEDIR/FinalCD/pool/main/u/ubuntu-meta/ubuntu-desktop*deb
                mv ubuntu-desktop*.deb  $BASEDIR/FinalCD/pool/main/u/ubuntu-meta/

                cp $EXTRASDIR/preseed/$SEEDFILE $BASEDIR/FinalCD/preseed/$SEEDFILE

        fi

        if [ ! -f "$EXTRASDIR/isolinux/isolinux.cfg" ]; then
                cat $CDSOURCEDIR/isolinux/isolinux.cfg | sed "s/^APPEND.*/APPEND   preseed\/file=\/cdrom\/preseed\/$SEEDFILE vga=normal initrd=\/install\/initrd.gz ramdisk_size=16384 root=\/dev\/rd\/0 DEBCONF_PRIORITY=critical debconf\/priority=critical rw --/" > $BASEDIR/FinalCD/isolinux/isolinux.cfg
        fi

        echo "OK"
fi

if [ ! -z "$USPLASH" ]; then
        echo "Modifying Usplash (NOTE: libgd2-dev required)"

        cd $SOURCEDIR
        if [ ! -d usplash ]; then
                mkdir usplash
        fi
        cd usplash
        SPLASH=`find * -maxdepth 1 -type d -name "usplash*" -type d -print`
        if [ -z "$SPLASH" ]; then
                apt-get source usplash
                SPLASH=`find * -maxdepth 1 -type d -name "usplash*" -type d -print`
        fi
        if [ -z "$SPLASH" ]; then
                echo "Cannot download USPLASH source. Exiting."
                exit
        fi

        cp $USPLASH $SOURCEDIR/usplash/$SPLASH/usplash-artwork.png
        cd $SOURCEDIR/usplash/$SPLASH
        dpkg-buildpackage -rfakeroot -m"$MYGPGKEY" -k"$MYGPGKEY" >/dev/null
        cd ..
        rm -f $BASEDIR/FinalCD/pool/main/u/usplash/usplash*deb
        mv usplash*.deb $BASEDIR/FinalCD/pool/main/u/usplash/
fi

echo "Creating apt package list.."
cd $BASEDIR/FinalCD

apt-ftparchive -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-deb.conf
apt-ftparchive -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-udeb.conf
if [ ! -z $EXTRASDIR ]; then
        if [ ! -f $BASEDIR/FinalCD/dists/$DIST/main/binary-i386/Release ]; then                cat $BASEDIR/FinalCD/dists/$DIST/main/binary-i386/Release | sed 's/Component: main/Component: extras/' > $BASEDIR/FinalCD/dists/$DIST/extras/binary-i386/Release
        fi
        ## Henrique Haas - check if exsits extras dists directory     
        if [ ! -d $BASEDIR/finalcd/dists/$DIST/extras/binary-i386 ]; then
                mkdir -p $BASEDIR/finalcd/dists/$DIST/extras/binary-i386
        fi
        apt-ftparchive -c $SOURCEDIR/apt.conf generate $SOURCEDIR/apt-ftparchive-extras.conf
fi




# Kill the existing release file
rm -f $BASEDIR/FinalCD/dists/$DIST/Release*

apt-ftparchive -c $SOURCEDIR/apt.conf release dists/$DIST/ > $BASEDIR/FinalCD/dists/$DIST/Release

echo "$GPGKEYPHRASE" | gpg --default-key "$MYGPGKEY" --passphrase-fd 0 --output $BASEDIR/FinalCD/dists/$DIST/Release.gpg -ba $BASEDIR/FinalCD/dists/$DIST/Release
echo "OK"

cd $BASEDIR/FinalCD
echo -n "Updating md5 checksums.. "
chmod 666 md5sum.txt
rm -f md5sum.txt
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
echo "OK"

cd $BASEDIR/FinalCD
echo "Creating and ISO image..."
mkisofs -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -hide-rr-moved -o $BASEDIR/$CDNAME -R $BASEDIR/FinalCD/

echo "CD Available in $BASEDIR/$CDNAME"
echo "You can now remove all files in:"
echo " - $BASEDIR/FinalCD"

# Unmount the old CD
umount $CDSOURCEDIR

