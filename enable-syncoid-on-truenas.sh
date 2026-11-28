#!/usr/bin/env bash

# Set script to exit on error
set -e
set -o pipefail
set -u

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
VERSIONEDSCRIPTS="0 1 3"
CONF="4 5"
SYSD="6 7 8"

# Vars from here down shouldn't need changing
# iXSystems puts decoy symbolic links in /usr/local/bin
# We need to temporarily move them out of the way
APT_PROGRAMS=(
  "apt"
  "apt-cache"
  "apt-cdrom"
  "apt-config"
  "apt-extracttemplates"
  "apt-ftparchive"
  "apt-get"
  "apt-key"
  "apt-mark"
  "apt-sortpkgs"
  "dpkg"
)

APT_DECOY_LINK_NAME="pkg_mgmt_disabled"
APT_PROGRAMS_TEMP_DIR="/usr/local/bin-disabled"

SCRIPTS_DIR="/usr/local/bin"
LINKS_DIR="/usr/local/sbin"
MORELINKS_DIR="/usr/sbin"
CONF_DIR="/etc/sanoid"
SYSD_DIR="/etc/systemd/system"
LOGFILE="/var/log/setup-script.log"
APT_SOURCES_PATH="/etc/apt/sources.list.d/"
APT_SOURCES_FILE="debian_syncoid.sources"

CHECKSTRING='production+truenas'
KERNEL=$(uname -a)
UPGRADE=0


###################
# Functions       #
###################
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -i DIR   Path to a folder containing sanoid source files
  -f       Force mode; skip the check it's running on TrueNAS
  -u       Upgrade mode; skip the installed-scripts check
  -h       Show this help and exit
EOF
}

while getopts ":i:hfu" opt; do
  case $opt in
    f)
      KERNEL="$CHECKSTRING"
      ;;
    h)
      usage
      exit 0
      ;;
    u)
      UPGRADE=1
      ;;
    i)
      SANOID_FILES_PATH="$OPTARG"
      ;;
    :)
      echo "Option -$OPTARG requires the path to a folder with sanoid source files" >&2
      usage >&2
      exit 1
      ;;
    \?)
      echo "Error: invalid option -$OPTARG." >&2
      usage >&2
      exit 1
      ;;
  esac
done


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
echo "===========================================================";
echo "                Starting script execution";
echo "===========================================================";

# Test if running on a TrueNAS system
if [[ ! "$KERNEL" == *"$CHECKSTRING"* ]]; then
    echo "-----------------------------------------------------------";
    echo " Error - NOT on TrueNAS. Script intended only for TrueNAS! ";
    echo "         (can override with -f but why would you??)        ";
    echo "-----------------------------------------------------------";
    exit 2;
fi

if [[ $UPGRADE == 1 ]] ; then
  echo "-- SKIPPING check if scripts installed"
else
  # Check to see if sanoid et al already installed and working
  echo "-- Checking if scripts already installed"
  (
    set +e
    SCRIPTSCOUNT=0
    INSTALLED=0
    for ITEM in $VERSIONEDSCRIPTS ; do
      ((SCRIPTSCOUNT +=1))
      if "${SANOID_FILES[$ITEM]}" --version 2>/dev/null; then
        ((INSTALLED +=1));
      else
        echo "   ${SANOID_FILES[$ITEM]} not installed" ;
      fi
    done
    if [ $SCRIPTSCOUNT == $INSTALLED ] ; then
      echo "All scripts installed already.  Exiting.";
      echo "    (can be overridden with -u to continue anyway.)";
      exit 3;
    fi
  ) || exit 3
fi

# Check if all sanoid files available
echo
echo "-- Finding required sanoid files "
if [[ -d "$SANOID_FILES_PATH" ]]; then
  echo "   Using local source, NOT downloading from github."
else
  echo "-- Getting required sanoid files "
  echo "   Downloading source from github."
  # get url for latest tar ball from git hub
  LATEST_TARBALL_URL=$(curl -s "$API_URL" | jq -r '.[0].tarball_url')

  # get latest tar ball from git hub
  curl -Lo "$LATEST_TARBALL_NAME" "$LATEST_TARBALL_URL"

  # get the top dir name inside tarball - its based on git commit id, so unpredictable
  TOP_DIR_NAME=$(tar -tf $LATEST_TARBALL_NAME --exclude "*/*"  | awk -F/ '{print $1}')
  tar -xf "$LATEST_TARBALL_NAME"
  mv -v "$TOP_DIR_NAME" "$SANOID_FILES_PATH"
fi

echo
echo -n "-- Checking required sanoid files "
for FILE in "${SANOID_FILES[@]}" ; do
    ([ -r "${SANOID_FILES_PATH}/${FILE}" ] && echo -n '.') || (echo; echo "Missing $FILE, exiting" && exit 1)
done
echo


echo
echo "-- Remounting usr as read write"
DATASET=$(findmnt -fn --output=source --mountpoint /usr)
if [ -z "$DATASET" ] ; then
    echo "   Error - couldn't determine /usr mount";
    exit 1;
else
    echo "   Completed" ;
    mount -o remount,rw "$DATASET";
fi


# Checking if apt not executable and reversing
# Seems version dependant? (pre Golden Eye)
echo
echo "-- Adding executable flag apt utilities if required"
if [[ ! -x /bin/apt ]]; then
  for program in "${APT_PROGRAMS[@]}"; do
    /usr/bin/chmod -c +x "/bin/${program}"
  done
fi

# Checking if apt programs in usr/local/bin are decoy links
# Seems version dependant?
echo
echo "-- Moving decoy symbolic links if required"
if [[ -L "/usr/local/bin/${APT_PROGRAMS[0]}" && "$(basename "$(readlink "/usr/local/bin/${APT_PROGRAMS[0]}")")" == "$APT_DECOY_LINK_NAME" ]]; then
  mkdir "$APT_PROGRAMS_TEMP_DIR"
  for program in "${APT_PROGRAMS[@]}"; do
    mv -v "/usr/local/bin/${program}" "${APT_PROGRAMS_TEMP_DIR}/"
  done
fi

# Create newer style debian.sources file
echo
echo "-- Getting apt release name"
echo
CODENAME="$(lsb_release -cs)"
if [ -z "$CODENAME" ] ; then
    echo "   Error - couldn't determine debian codename";
    exit 4;
else
  if [[ -f "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}" ]]; then
    echo "   Apt sources exists - moving to -prev"
    mv -v "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}" "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}-prev"
  fi
  echo "-- Creating ${APT_SOURCES_FILE}";
    cat << EOF >> "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}"

Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: $CODENAME
Components: main
Trusted: yes
EOF
fi


# Install prerequisites
echo
echo "-- Updating repositories"
/bin/apt-get update

echo
echo "-- Installing prerequisites via apt"
/bin/apt-get install -y libcapture-tiny-perl libconfig-inifiles-perl pv lzop mbuffer


echo
echo "-- Undoing additions to apt sources";
# Remove added sources list
rm -v "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}"

if [[ -f "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}-prev" ]]; then
  echo "   Replacing previous copy of ${APT_SOURCES_FILE}"
  mv -v "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}-prev" "${APT_SOURCES_PATH}/${APT_SOURCES_FILE}"
fi

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
echo "-- Symlinking scripts to ${LINKS_DIR}"
for ITEM in $SCRIPTS ; do
    [[ -L "${LINKS_DIR}/${SANOID_FILES[$ITEM]}" ]] || ln -vs "${SCRIPTS_DIR}/${SANOID_FILES[$ITEM]}" "${LINKS_DIR}/" ;
done
echo
echo "-- Symlinking scripts to ${MORELINKS_DIR}"
for ITEM in $SCRIPTS ; do
    [[ -L "${MORELINKS_DIR}/${SANOID_FILES[$ITEM]}" ]] || ln -vs "${SCRIPTS_DIR}/${SANOID_FILES[$ITEM]}" "${MORELINKS_DIR}/" ;
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
echo "-- Moving systemd files into place"
for ITEM in $SYSD ; do
    cp -v "${SANOID_FILES_PATH}/${SANOID_FILES[$ITEM]}" "$SYSD_DIR" ;
done

# Get systemd to see new files
echo
echo "-- Getting systemd to find new service files"
/usr/bin/systemctl daemon-reload

# Enable sanoid timer
echo
echo "-- Enabling the sanoid timer"
/usr/bin/systemctl enable --now sanoid.timer

# Put decoy files back and remove temp dir
echo
echo "-- Replacing decoy links and removing temp dir if required"
if [[ -e "${APT_PROGRAMS_TEMP_DIR}/${APT_PROGRAMS[0]}" || -L "${APT_PROGRAMS_TEMP_DIR}/${APT_PROGRAMS[0]}" ]] ; then
  mv -v "${APT_PROGRAMS_TEMP_DIR}"/* "/usr/local/bin/"
  rmdir -v "$APT_PROGRAMS_TEMP_DIR"
fi

# Put usr back as was
echo
echo "-- Remounting usr as read only"
/usr/bin/mount -o remount,ro "$DATASET";

# Check programs by outputting version information
echo
echo "-- Confirming programs installed and on path"
syncoid --version
findoid --version
sanoid --version

# Profit?
echo
echo "========================================================";
echo "        Script execution completed successfully!"
echo "========================================================";

#  vim: set filetype=sh syntax=sh ts=4 sw=4 tw=0 :
