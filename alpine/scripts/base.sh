#!/usr/bin/env bash
# Base configuration of the box (runs as root, libvirt build only; the
# VirtualBox box is made from the finished libvirt image).
set -euxo pipefail

# What the image is (kept in the build log).
cat /etc/alpine-release; uname -a
apk info -e linux-virt linux-lts linux-edge || true
ls /boot; cat /boot/limine/limine.conf
cloud-init status --long || true
tail -40 /var/log/cloud-init-output.log || true
apk info -e bash doas doas-sudo-shim sudo || true
cat /etc/doas.conf /etc/doas.d/* 2>/dev/null || true
cat /etc/network/interfaces || true
rc-update show -v | grep -v '^ *| *$' || true

# What the box was built from, for anyone inspecting a VM.
cat > /etc/hako-release <<REL
BOX=$HAKO_BOX
VERSION=$HAKO_VERSION
IMAGE=$HAKO_IMAGE
REL

# Bring the image up to date at build time; the box version is the date.
apk update
apk fix
apk upgrade --available

# sudo for Vagrant: installed, with its rule, by the first Packer step (the
# image only has doas, whose build-seed rule cleanup.sh removes).
visudo -c

# Vagrant logs in with bash; rsync serves synced folders where vboxsf
# cannot.
apk add rsync
sed -i 's#^\(vagrant:.*:\)/bin/sh$#\1/bin/bash#' /etc/passwd
grep '^vagrant:' /etc/passwd

# Vagrant-friendly sshd: no reverse DNS lookups on login.
install -d -m 0755 /etc/ssh/sshd_config.d
printf 'UseDNS no\n' > /etc/ssh/sshd_config.d/10-hako.conf
rc-update add sshd default

# Containers need the cgroup file system, which OpenRC's cgroups service
# mounts (Docker's own init script would start it; the image does not).
rc-update add cgroups boot

# No boot menu wait.
sed -i 's/^timeout:.*/timeout: 0/' /boot/limine/limine.conf
grep -q '^timeout:' /boot/limine/limine.conf || sed -i '1i timeout: 0' /boot/limine/limine.conf
cat /boot/limine/limine.conf /etc/limine/limine-efi-updater.conf 2>/dev/null || true

# cloud-init: only react to a NoCloud/ConfigDrive seed (see the files).
install -m 0644 /tmp/hako/99-hako.cfg /etc/cloud/cloud.cfg.d/99-hako.cfg
install -m 0644 /tmp/hako/ds-identify.cfg /etc/cloud/ds-identify.cfg
