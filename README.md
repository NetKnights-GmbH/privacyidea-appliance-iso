# privacyidea-appliance-iso

Create an installation ISO based on [ubuntu server](https://www.ubuntu.com/server) 16.04
to install the [privacyIDEA server](https://github.com/privacyidea/privacyidea)
and [Appliance](https://github.com/NetKnights-GmbH/privacyidea-appliance)

The process is loosely based on the
[Install CD Customization](https://help.ubuntu.com/community/InstallCDCustomization)
documentation and the [script](https://help.ubuntu.com/community/InstallCDCustomization/Scripts)
by Leigh Purdie.

#### Requirements
You need a current point-release of the ubuntu server iso image (16.04.5 as of 2018/09/03). If 
the image is not locally available, it will be downloaded from the ubuntu servers.

You also need a template machine with a freshly installed `pi-appliance` to
collect all the updated packages.

The script makes extensive use of `sudo` to gain root privileges, so make sure it is available 
and working. Alternatively the script can be run as root as well.

#### Usage
Some settings must be configured in the `build_iso.sh` script (i.e. the template server).

Then just run `./build_iso.sh [-i <base iso-file>] <working directory>` and if everything works, 
an iso-image will be available in the working directory.

Always test the image before shipping it in case some errors crept in during the build.
