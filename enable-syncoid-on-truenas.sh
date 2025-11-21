#!/usr/bin/env bash

# Set script to exit on error
set -e
set -o pipefail
set -u

# FIXME
# should use -v or --verbose to control terminal output

###################
# Variable set up #
###################
# If download is used
LATEST_TARBALL_NAME='sanoid.latest.tar.gzip'
API_URL='https://api.github.com/repos/jimsalterjrs/sanoid/releases'

# If already downloaded place files here
# note - keep structure with systemd files in packages/debian/
SANOID_FILES_PATH="sanoid.latest"

SANOID_FILES=(
"findoid"
"sanoid"
"sleepymutex"
"syncoid"
"sanoid.conf"
"sanoid.defaults.conf"
"packages/debian/sanoid.sanoid-prune.service"
"packages/debian/sanoid.service"
"packages/debian/sanoid.timer"
)

# If you do change the file list, change these arrays to match
SCRIPTS="0 1 2 3"
CONF="4 5"
SYSD="6 7 8"

# These shouldn't need changing
SCRIPTS_DIR="/usr/local/bin"
LINKS_DIR="/usr/local/sbin"
CONF_DIR="/etc/sanoid"
SYSD_DIR="/etc/systemd/system"
LOGFILE="/var/log/setup-script.log"
DATESTAMP=$(date "+%Y-%m-%d_%s")
APT_SOURCES_PATH="/etc/apt"
APT_SOURCES_FILE="sources.list"


# Determine if downloading sanoid et al or using existing folder
while getopts ":i:h" opt; do
  case $opt in
    i)
      SANOID_FILES_PATH="$OPTARG"
      ;;
    :)
      echo "Option -$OPTARG requires the path to a folder with sanoid source files" >&2
      exit 1
      ;;
    h|\?)
      echo "Usage: $(basename "$0") [-i sanoid_source_folder]"
      exit 1
      ;;
  esac
done


if [[ -d "$SANOID_FILES_PATH" ]]; then
  echo "Using local source, NOT downloading from github."
else
  echo "Downloading source from github."
  # get url for latest tar ball from git hub
  LATEST_TARBALL_URL=$(curl -s "$API_URL" | jq -r '.[0].tarball_url')

  # get latest tar ball from git hub
  curl -Lo "$LATEST_TARBALL_NAME" "$LATEST_TARBALL_URL"

  # get the top dir name inside tarball - its based on git commit id, so unpredictable
  TOP_DIR_NAME=$(tar -tf $LATEST_TARBALL_NAME --exclude "*/*"  | awk -F/ '{print $1}')
  tar -xf "$LATEST_TARBALL_NAME"
  mv -v "$TOP_DIR_NAME" "$SANOID_FILES_PATH"
fi


################
# Script start #
################

# Check if run with enough privileges
ISROOT=$(id -u)
if [ "$ISROOT" -ne 0 ]; then
    echo "-----------------------------------------------------------";
    echo " Error - insufficient privileges.  Run with sudo or root. ";
    echo "-----------------------------------------------------------";
    exit 1;
fi


# Enable logging
exec > >(tee -i "$LOGFILE")
exec 2>&1


# Start
echo
echo "========================================================";
echo "              Starting script execution";
echo "========================================================";

# Check if all sanoid files available
echo
echo -n "-- Checking required sanoid files "
for FILE in "${SANOID_FILES[@]}" ; do
    ([ -r "${SANOID_FILES_PATH}/${FILE}" ] && echo -n '.') || (echo "Missing $FILE, exiting" && exit 1)
done
echo


# Attempt to remount /usr read+write
echo
echo "-- Remounting usr as read write"
DATASET=$(findmnt -fn --output=source --mountpoint /usr)
if [ -z "$DATASET" ] ; then
    echo "Error - couldn't determine /usr mount";
    exit 1;
else
    echo "Completed" ;
    mount -o remount,rw "$DATASET";
fi


# Re-enabling apt utilities
echo
echo "-- Adding executable flag to re-enable apt utilities"
chmod -c +x /bin/apt*
chmod -c +x /usr/bin/dpkg

# Update sources list
# FIXME should check if additions are already in file and not dupicate them
echo
echo "-- Working on apt sources"
echo
CODENAME="$(lsb_release -cs)"
if [ -z "$CODENAME" ] ; then
    echo "Error - couldn't determine debian codename";
    exit 1;
else
    echo "-- Backing up sources.list";
    cp -v "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}" "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}-${DATESTAMP}"
    echo
    echo "-- Updating sources.list";
    cat << EOF >> "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}"
deb http://deb.debian.org/debian $CODENAME main
deb-src http://deb.debian.org/debian $CODENAME main
EOF
fi


# Install prerequisites
echo
echo "-- Updating repositories"
apt-get update

echo
echo "-- Installing prerequisites via apt"
apt-get install -y libcapture-tiny-perl libconfig-inifiles-perl pv lzop mbuffer


# Restore sources list
echo
echo "-- Restoring sources.list";
echo cp -vf "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}-${DATESTAMP}" "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}"


#FIXME include Br46
# Make sure scripts are executable
echo
echo "-- Setting scripts as executable"
for ITEM in $SCRIPTS ; do
    chmod -c +x  "${SANOID_FILES_PATH}/${SANOID_FILES[$ITEM]}" ;
done

# Copy scripts to usr local bin
echo
echo "-- Copying scripts into place"
for ITEM in $SCRIPTS ; do
    cp -v "${SANOID_FILES_PATH}/${SANOID_FILES[$ITEM]}" "$SCRIPTS_DIR" ;
done

# Symlink scripts into usr sbin
echo
echo "-- Symlinking scripts"
for ITEM in $SCRIPTS ; do
    [[ -L "${LINKS_DIR}/${SANOID_FILES[$ITEM]}" ]] || ln -vs "${SCRIPTS_DIR}/${SANOID_FILES[$ITEM]}" "${LINKS_DIR}/" ;
done

# Create conf dir if required
echo
echo "-- Creating conf dir if required"
mkdir -pv "${CONF_DIR}"

# Copy conf files into conf dir
echo
echo "-- Copying conf files into place"
for ITEM in $CONF ; do
    cp -v "${SANOID_FILES_PATH}/${SANOID_FILES[$ITEM]}" "$CONF_DIR" ;
done

# Copy services and timer into place and activate
echo
echo "-- Moving conf files into place"
for ITEM in $SYSD ; do
    cp -v "${SANOID_FILES_PATH}/${SANOID_FILES[$ITEM]}" "$SYSD_DIR" ;
done

# Get systemd to see new files
echo
echo "-- Getting systemd to find new service files"
systemctl daemon-reload

# Enable sanoid timer
echo
echo "-- Enabling the sanoid timer"
systemctl enable --now sanoid.timer


# Put usr back as was
echo
echo "-- Remounting usr as read only"
mount -o remount,ro "$DATASET";

# Profit?
echo
echo "========================================================";
echo "        Script execution completed successfully!"
echo "========================================================";

#  vim: set filetype=sh syntax=sh ts=4 sw=4 tw=0 :
