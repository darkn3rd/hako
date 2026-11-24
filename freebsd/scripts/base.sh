#!/bin/sh
# Base configuration of the box (runs as root, libvirt build only; the
# VirtualBox box is made from the finished libvirt image).
set -eux

# What the image is (kept in the build log).
freebsd-version -kru; uname -a
cat /etc/rc.conf; ls /etc/rc.conf.d 2>/dev/null || true
cat /boot/loader.conf 2>/dev/null || true
tunefs -p / 2>&1 || true
pkg which /bin/sh 2>&1 || true

# What the box was built from, for anyone inspecting a VM.
cat > /etc/hako-release <<REL
BOX=$HAKO_BOX
VERSION=$HAKO_VERSION
IMAGE=$HAKO_IMAGE
REL

# Bring the image up to date at build time; the box version is the date.
# The base system comes from freebsd-update, or from pkg where it is
# installed as packages (pkgbase).
export ASSUME_ALWAYS_YES=yes
if pkg which -q /bin/sh >/dev/null 2>&1; then
  pkg upgrade -y
else
  PAGER=cat freebsd-update --not-running-from-cron fetch
  PAGER=cat freebsd-update --not-running-from-cron install || true   # exits 2 when there is nothing to install
  pkg upgrade -y
fi

# rsync serves the shared folder (Vagrant has no VirtualBox shared folder
# support for FreeBSD guests).
pkg install -y rsync

# Networking: DHCP on every NIC, whatever its name (vtnet0 on QEMU and
# VirtualBox's virtio NIC, em0 on an Intel one), in the background rather
# than holding up the boot; and sshd.
sysrc ifconfig_DEFAULT="DHCP" sshd_enable="YES"

# No boot menu wait (see the file).
install -d /boot/loader.conf.d
install -m 0644 /tmp/hako/loader.conf.hako /boot/loader.conf.d/hako.conf

# Vagrant-friendly sshd: no reverse DNS lookups on login.
sed -i '' 's/^#*UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
grep -q '^UseDNS no' /etc/ssh/sshd_config || echo 'UseDNS no' >> /etc/ssh/sshd_config
