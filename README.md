# Syncoid-Scale
Install Syncoid on TrueNAS Scale, or reinstall after an OS update

## Background
[TrueNAS Scale](https://www.truenas.com/truenas-scale/) is great NAS operating system, based on [Debian](https://www.debian.org) and incorporating the [ZFS](https://zfsonlinux.org/) file system.

It has built in software to do replication with other systems, with options for cloud sync, rsync and with zfs replication.

The zfs replication option, however, works best with another TrueNAS system.

Some users prefer [Sanoid](https://github.com/jimsalterjrs/sanoid) and related programs to do zfs replication, which is a Perl script and related config files and systemd units.

Sanoid can be easily installed on most linux operating systems via the native package manager, or manually.  Installing on TrueNAS Scale is not as simple, however, because the Debian operating system underneath is deliberately locked down in a few ways, to help the reliability and predictability of TrueNAS Scale.  The NAS software is provided as a complete appliance, and it's developers strongly encourage not changing the underpinning OS directly.

Additionally, updates to TrueNAS Scale are provided somewhat atomically.  If changes are made to files outside the data storage areas, the changes are overwritten on some (every?) operarting system update.

This script makes it easier to break the 'no end user servicable parts inside' sticker they've applied to TrueNAS.  Please note this is strictly at your own risk.  If it breaks, you get to keep the pieces, and I get to say "I told you so"

## Requirements and Usage

You will need an account on the NAS that can use sudo (or su to root).  
Typically the first local user you set up will be able to do so.

Copy [enable-syncoid-on-truenas.sh](https://github.com/furicle/Syncoid-Scale/blob/main/enable-syncoid-on-truenas.sh) script to that users directory, and ssh in or use the web console to log in as that user.

Run ``sudo bash enable-syncoid-on-truenas.sh``

The script will download the latest source code from the sanoid github site, unzip the tarball, and copy the following files into place.

* [findoid](https://github.com/jimsalterjrs/sanoid/blob/master/findoid)
* [sanoid](https://github.com/jimsalterjrs/sanoid/blob/master/sanoid)
* [sleepymutex](https://github.com/jimsalterjrs/sanoid/blob/master/sleepymutex)
* [syncoid](https://github.com/jimsalterjrs/sanoid/blob/master/syncoid)
* [sanoid.conf](https://github.com/jimsalterjrs/sanoid/blob/master/sanoid.conf)
* [sanoid.defaults.conf](https://github.com/jimsalterjrs/sanoid/blob/master/sanoid.defaults.conf)
* [sanoid-prune.service](https://github.com/jimsalterjrs/sanoid/blob/master/sanoid-prune.service)
* [sanoid.service](https://github.com/jimsalterjrs/sanoid/blob/master/sanoid.service)
* [sanoid.timer](https://github.com/jimsalterjrs/sanoid/blob/master/sanoid.timer)

Edit the sanoid.conf file to match _your_ requirements.

The script should run to the end without error and report `completed successfully`
Some warnings from apt are normal, but not errors.

If it does not, please review the output and/or the log file at `/var/log/setup-script.log` carefully.

By default, the script puts /usr back as a read-only folder, but that does not happen if the run is interupted.  The next system restart will restore the read-only state as well.

After every TrueNAS update, you should check if sanoid exists and is executable, and re-run this script if it's not present.

If you want to avoid the downloading from github, place the unzipped source into the same folder as the enable script, and run the script with ``-i folder_with_code``.  Note if it doesn't find the folder as named, it will download anyway.

## More Info

For more information, and discussions of ZFS or Sanoid, I recommend the [Practical ZFS](https://discourse.practicalzfs.com) discussion site.

## Future Changes etc...

Feedback, suggestions and patches are welcome, although speedy responses are not guaranteed.
:-)
