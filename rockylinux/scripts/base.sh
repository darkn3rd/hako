#!/usr/bin/env bash
# Base configuration of the box (runs as root, libvirt build).
set -euxo pipefail

# Let the build-time cloud-init run finish (user creation, growpart).
cloud-init status --wait || true

printf 'BOX=%s\nVERSION=%s\nIMAGE=%s\n' "$HAKO_BOX" "$HAKO_VERSION" "$HAKO_IMAGE" > /etc/hako-release

# Bring the image up to date at build time; the box version is the date.
dnf -y upgrade --refresh

# Ready for Docker: the cloud image has only kernel-modules-core, and
# br_netfilter, nft_compat, the xt_* matches and the iptable_* tables Docker
# loads are in kernel-modules-extra. (Installed for the upgraded kernel;
# kernel updates bring the matching one.)
dnf -y install kernel-modules-extra

# Vagrant-friendly sshd: no reverse DNS lookups on login.
install -d -m 0755 /etc/ssh/sshd_config.d
printf 'UseDNS no\n' > /etc/ssh/sshd_config.d/10-hako.conf

# No background metadata refreshes after `vagrant up`.
systemctl disable --now dnf-makecache.timer || true

# No rngd: the kernel reads a hardware RNG (the box's Vagrantfile adds a
# virtio one for QEMU/libvirt) by itself, and without one rngd only fails.
dnf -y remove rng-tools

# No crash kernel: kdump reserves up to 256 MB of a small VM's memory and
# adds a service to every boot.
systemctl disable kdump.service
grubby --update-kernel=ALL --remove-args=crashkernel
sed -i 's/ crashkernel=[^ "]*//' /etc/default/grub

# No GRUB menu wait (the image waits 1 s): one kernel, no one at the console.
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

# Networking: no per-NIC profiles in the box. NetworkManager then brings up
# every ethernet NIC with DHCP on its own (an in-memory "Wired connection"),
# whatever its name or MAC address, and a profile Vagrant or a cloud-init
# seed adds for a NIC takes over that NIC. cleanup.sh removes the profile
# the build's cloud-init wrote (it is tied to the build VM's MAC address).
! grep -rqs '^no-auto-default' /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d /usr/lib/NetworkManager/conf.d

# cloud-init: only react to a NoCloud/ConfigDrive seed, and stay off for a
# boot without one (see both files).
install -m 0644 /tmp/hako/99-hako.cfg /etc/cloud/cloud.cfg.d/99-hako.cfg
install -m 0644 /tmp/hako/ds-identify.cfg /etc/cloud/ds-identify.cfg
