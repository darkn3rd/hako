#!/usr/bin/env bash
# Base configuration of the box (runs as root, libvirt build).
#
# Packages stay as Gentoo built them: the image is rebuilt weekly, and an
# @world update here would compile from source (the dist-kernel included),
# which turns a minutes-long build into hours. The box version is the build
# date; the image it came from is recorded in /etc/hako-release.
set -euxo pipefail

# Let the build-time cloud-init run finish (user creation, growpart).
cloud-init status --wait || true

uname -r
findmnt -no SOURCE,FSTYPE /

printf 'BOX=hako/gentoo\nVERSION=%s\nIMAGE=%s\n' "$HAKO_VERSION" "$HAKO_IMAGE" > /etc/hako-release

# Binary packages from Gentoo's official binhost by default (the image
# already lists it in /etc/portage/binrepos.conf and verifies signatures),
# so emerge in a VM installs prebuilt packages where they match instead of
# compiling everything. Turn off with FEATURES="-getbinpkg" or --getbinpkg=n.
if ! grep -q getbinpkg /etc/portage/make.conf; then
  printf '\n# Added by hako: use the binhost in binrepos.conf when a package matches.\nFEATURES="${FEATURES} getbinpkg"\n' \
    >> /etc/portage/make.conf
fi

# sshd is not enabled in the image (cloud-init starts it for the build).
systemctl enable sshd.service

# A VM takes its clock from the host; don't hold boot for NTP if anything
# pulls this in. systemd-timesyncd still keeps time afterwards.
systemctl disable systemd-time-wait-sync.service 2>/dev/null || true

# Vagrant-friendly sshd: no reverse DNS lookups on login.
install -d -m 0755 /etc/ssh/sshd_config.d
printf 'UseDNS no\n' > /etc/ssh/sshd_config.d/10-hako.conf
grep -Eq '^Include /etc/ssh/sshd_config.d/' /etc/ssh/sshd_config ||
  sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config

# Networking: exactly one systemd-networkd file, matching any ethernet NIC
# by name (cloud-init's per-NIC file is removed at cleanup).
install -m 0644 /tmp/hako/99-hako-ethernet.network /etc/systemd/network/99-hako-ethernet.network
systemctl enable systemd-networkd.service

# cloud-init: only react to a NoCloud/ConfigDrive seed, and stay off for a
# boot without one (see both files).
install -m 0644 /tmp/hako/99-hako.cfg /etc/cloud/cloud.cfg.d/99-hako.cfg
install -m 0644 /tmp/hako/ds-identify.cfg /etc/cloud/ds-identify.cfg

# No hardware firmware in a VM: linux-firmware is about 640 MB of the image.
# Portage needs the ebuild repository even to remove a package, and the image
# ships none, so fetch a snapshot (cleanup.sh deletes it again). --depclean
# refuses if anything still depends on the package.
emerge-webrsync --quiet
emerge --deselect sys-kernel/linux-firmware
emerge --depclean --quiet sys-kernel/linux-firmware
! portageq has_version / sys-kernel/linux-firmware
du -sh /usr/lib/firmware 2>/dev/null || true

# BIOS boot on amd64, next to UEFI. The image is UEFI-only, but
# vagrant-libvirt starts VMs with BIOS (SeaBIOS) unless the user configures
# a UEFI loader, and then nothing boots. The 1 MiB gap before the ESP holds
# a GRUB BIOS boot partition; the image's GRUB already has the i386-pc
# platform. Both GRUBs read the same /boot/grub/grub.cfg.
if [[ $(uname -m) == x86_64 ]] && ! sgdisk -p /dev/vda | awk '$6 == "EF02"' | grep -q .; then
  sgdisk -a 1 -n 0:34:2047 -t 0:EF02 -c 0:biosboot /dev/vda
  grub-install --target=i386-pc --boot-directory=/boot /dev/vda
fi

# No GRUB menu wait (the default is 5 s): there is one kernel and no one at
# the console. The kernel lives on the ESP, mounted at /boot.
#
# grub.cfg is written only now, after linux-firmware is gone: that package
# installs /boot/amd-uc.img (AMD microcode), grub-mkconfig adds it to the
# initrd line, and when the file is missing GRUB drops the whole initrd, so
# the kernel boots without its initramfs and panics (no root filesystem).
sed -i '/^#\?GRUB_TIMEOUT=/d; /^#\?GRUB_TIMEOUT_STYLE=/d' /etc/default/grub
printf 'GRUB_TIMEOUT=0\nGRUB_TIMEOUT_STYLE=hidden\n' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
# Every kernel and initrd grub.cfg names must exist on /boot.
for f in $(awk '$1 == "linux" { print $2 } $1 == "initrd" { for (i = 2; i <= NF; i++) print $i }' \
             /boot/grub/grub.cfg | sort -u); do
  test -f "/boot$f" || { echo "grub.cfg names /boot$f, which does not exist" >&2; exit 1; }
done

# Per-VM SSH host keys, generated on first boot.
install -m 0644 /tmp/hako/hako-ssh-hostkeys.service /etc/systemd/system/hako-ssh-hostkeys.service
systemctl enable hako-ssh-hostkeys.service
