#!/usr/bin/env bash
# Base configuration of the box (runs as root, libvirt build).
set -euxo pipefail

# Let the build-time cloud-init run finish (user creation, growpart).
cloud-init status --wait || true

# The image initialises its pacman keyring on first boot (pacman-init.service).
systemctl is-active --quiet pacman-init.service || systemctl start pacman-init.service || true

# Bring the image up to date at build time; the box version is the date.
# The keyring goes first so packages signed by new keys verify.
pacman -Sy --noconfirm --needed archlinux-keyring
pacman -Su --noconfirm

# Build the initramfs without the autodetect hook, as arch-boxes does: with
# it, a kernel upgrade here keeps only the build VM's drivers (virtio), and
# the VirtualBox box, whose disk is on SATA (AHCI), could not find its root.
sed -i '/^default_options=/d' /etc/mkinitcpio.d/linux.preset
echo 'default_options="-S autodetect"' >> /etc/mkinitcpio.d/linux.preset
mkinitcpio -P

# Per-VM pacman keyring, created on first boot (see the unit). It replaces
# the image's pacman-init.service, which hako boxes would never run.
install -m 0644 /tmp/hako/hako-pacman-init.service /etc/systemd/system/hako-pacman-init.service
systemctl enable hako-pacman-init.service
systemctl disable pacman-init.service || true

# Vagrant-friendly sshd: no reverse DNS lookups on login.
install -d -m 0755 /etc/ssh/sshd_config.d
printf 'UseDNS no\n' > /etc/ssh/sshd_config.d/10-hako.conf

# Networking: exactly one systemd-networkd file, matching any ethernet NIC
# by name.
rm -f /etc/systemd/network/*.network
install -m 0644 /tmp/hako/99-hako-ethernet.network /etc/systemd/network/99-hako-ethernet.network
systemctl enable systemd-networkd.service

# cloud-init: only react to a NoCloud/ConfigDrive seed (see the file).
install -m 0644 /tmp/hako/99-hako.cfg /etc/cloud/cloud.cfg.d/99-hako.cfg

# Per-VM SSH host keys, generated on first boot.
install -m 0644 /tmp/hako/hako-ssh-hostkeys.service /etc/systemd/system/hako-ssh-hostkeys.service
systemctl enable hako-ssh-hostkeys.service
