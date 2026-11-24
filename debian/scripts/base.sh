#!/usr/bin/env bash
# Base configuration of the box (runs as root, libvirt build only; the
# VirtualBox box is made from the finished libvirt image).
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Let the build-time cloud-init run finish (user creation, growpart).
cloud-init status --wait || true

# What the box was built from, for anyone inspecting a VM.
cat > /etc/hako-release <<REL
BOX=$HAKO_BOX
VERSION=$HAKO_VERSION
IMAGE=$HAKO_IMAGE
REL

# Bring the image up to date at build time; the box version is the date.
apt-get update
apt-get -y -o Dpkg::Options::=--force-confnew dist-upgrade
apt-get -y autoremove --purge

# No background apt runs that grab the dpkg lock while a provisioner
# (Ansible, shell) wants it right after `vagrant up`.
systemctl disable apt-daily.timer apt-daily-upgrade.timer
systemctl disable unattended-upgrades.service 2>/dev/null || true

# Networking: systemd-networkd with one DHCP file for every ethernet NIC.
# The image's netplan config only describes the build NIC, so cleanup.sh
# removes it with cloud-init's. netplan itself stays, for cloud-init to use
# when a VM is given a seed.
ls -l /etc/netplan /etc/systemd/network || true
install -m 0644 /tmp/hako/99-hako-ethernet.network /etc/systemd/network/99-hako-ethernet.network
systemctl enable systemd-networkd.service
if dpkg -s ifupdown >/dev/null 2>&1; then apt-get -y purge ifupdown; fi

# GRUB: no menu wait. (grub.d snippets sort after the image's own.)
install -d /etc/default/grub.d
printf 'GRUB_TIMEOUT=0\nGRUB_TIMEOUT_STYLE=hidden\n' > /etc/default/grub.d/99-hako.cfg
update-grub

# Per-VM SSH host keys, generated on first boot (cloud-init normally does
# this, but it stays off without a seed).
install -m 0644 /tmp/hako/hako-ssh-hostkeys.service /etc/systemd/system/hako-ssh-hostkeys.service
systemctl enable hako-ssh-hostkeys.service

# cloud-init: only react to a NoCloud/ConfigDrive seed (see the files).
install -m 0644 /tmp/hako/99-hako.cfg /etc/cloud/cloud.cfg.d/99-hako.cfg
install -m 0644 /tmp/hako/ds-identify.cfg /etc/cloud/ds-identify.cfg
