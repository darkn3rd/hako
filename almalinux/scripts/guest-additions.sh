#!/usr/bin/env bash
# Install the VirtualBox Guest Additions (vboxsf shared folders etc). RHEL
# kernels have no vboxguest/vboxsf, so the modules are built from the Guest
# Additions ISO. The compiler and kernel-devel stay installed so the modules
# rebuild when the guest kernel is upgraded (kernel-devel is an install-only
# package, so dnf upgrade brings the matching one with each new kernel).
set -euxo pipefail

dnf -y install gcc make perl bzip2 tar elfutils-libelf-devel "kernel-devel-$(uname -r)"

mnt=$(mktemp -d)
mount -o loop,ro /tmp/VBoxGuestAdditions.iso "$mnt"
case $(uname -m) in
  aarch64) installer=VBoxLinuxAdditions-arm64.run ;;
  *)       installer=VBoxLinuxAdditions.run ;;
esac
# The installer exits 2 when it cannot load modules into the running
# kernel (e.g. no X11); the modules are verified below instead.
sh "$mnt/$installer" --nox11 || [ $? -eq 2 ]
umount "$mnt"
rm -rf "$mnt" /tmp/VBoxGuestAdditions.iso

modinfo vboxsf vboxguest
usermod -aG vboxsf vagrant
