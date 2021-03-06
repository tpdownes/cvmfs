#!/bin/bash

# source the common platform independent functionality and option parsing
script_location=$(dirname $(readlink --canonicalize $0))
. ${script_location}/common_setup.sh

# configuring apt for non-interactive environment
echo -n "configure package manager for non-interactive usage... "
export DEBIAN_FRONTEND=noninteractive
echo "done"

# sudo cannot resolve host name right after startup for some reason
echo -n "wait for sudo to work properly... "
timeout=1800
while sudo echo "foo" 2>&1 | grep -q "unable to resolve host"; do
  sleep 1
  timeout=$(( $timeout - 1 ))
  if [ $timeout -le 0 ]; then
    echo "FAIL!"
    exit 1
  fi
done
echo "done"

# update package manager cache
echo -n "updating package manager cache... "
sudo apt-get update > /dev/null || die "fail (apt-get update)"
echo "done"

# install latest version of libc to make sure it has the symbols from the build machine
echo -n "updating libc6, libstdc++6... "
install_from_repo libc6 || die "fail (libc6)"
install_from_repo libstdc++6 || die "fail (libstdc++6)"
echo "done"

# install package dependency resolve program
echo -n "installing gdebi-core... "
install_from_repo gdebi-core || die "fail (install gdebi-core)"
echo "done"

# install deb packages
echo "installing DEB packages... "
install_deb "$CONFIG_PACKAGES"
install_deb $CLIENT_PACKAGE
install_deb $SERVER_PACKAGE
install_deb $DEVEL_PACKAGE
install_deb $UNITTEST_PACKAGE

# installing WSGI apache module
echo "installing python WSGI module..."
install_from_repo libapache2-mod-wsgi    || die "fail (installing libapache2-mod-wsgi)"
install_from_repo default-jre            || die "fail (installing default-jre)"
sudo service apache2 restart > /dev/null || die "fail (restarting apache)"

# setup environment
echo -n "setting up CernVM-FS environment... "
sudo cvmfs_config setup                          || die "fail (cvmfs_config setup)"
sudo mkdir -p /var/log/cvmfs-test                || die "fail (mkdir /var/log/cvmfs-test)"
sudo chown sftnight:sftnight /var/log/cvmfs-test || die "fail (chown /var/log/cvmfs-test)"
if getent group fuse > /dev/null 2>&1; then
  attach_user_group fuse                         || die "fail (add fuse group to user)"
fi
sudo service autofs restart > /dev/null          || die "fail (restart autofs)"
sudo cvmfs_config chksetup > /dev/null           || die "fail (cvmfs_config chksetup)"
echo "done"

# install test dependencies
echo "installing test dependencies..."
install_from_repo gcc                           || die "fail (installing gcc)"
install_from_repo g++                           || die "fail (installing g++)"
install_from_repo make                          || die "fail (installing make)"
install_from_repo sqlite3                       || die "fail (installing sqlite3)"
install_from_repo linux-image-extra-$(uname -r) || die "fail (installing AUFS)"
install_from_repo bc                            || die "fail (installing bc)"
install_from_repo tree                          || die "fail (installing tree)"

# traffic shaping
install_from_repo trickle || die "fail (installing trickle)"

# install 'cvmfs_preload' build dependencies
install_from_repo cmake        || die "fail (installing cmake)"
install_from_repo libattr1-dev || die "fail (installing libattr1-dev)"
install_from_repo python-dev   || die "fail (installing python-dev)"

# install 'jq' (on 12.04 this needs the precise-backports repo)
if [ x"$(lsb_release -cs)" = x"precise" ]; then
  echo -n "enabling precise-backports... "
  sudo sed -i -e 's/^# \(.*precise-backports.*\)$/\1/g' /etc/apt/sources.list || die "fail (updating sources.list)"
  sudo apt-get update > /dev/null                                             || die "fail (apt-get update)"
  echo "done"
fi
install_from_repo jq || die "fail (installing jq)"

# On Ubuntu 16.04 install backported autofs
if [ "x$(lsb_release -cs)" = "xxenial" ]; then
  install_from_repo wget || die "fail (installing wget)"
  wget https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release_2.0-3_all.deb
  sudo dpkg -i cvmfs-release_2.0-3_all.deb || die "fail (installing cvmfs-release)"
  sudo apt-get update
  sudo apt-get install autofs || die "fail installing backported autofs"
  sudo cvmfs_config setup || die "re-running cvmfs setup"
  dpkg -s autofs
fi

# setting up the AUFS kernel module
echo -n "loading AUFS kernel module..."
sudo modprobe aufs || die "fail"
echo "done"

# increase open file descriptor limits
echo -n "increasing ulimit -n ... "
set_nofile_limit 65536 || die "fail"
echo "done"
