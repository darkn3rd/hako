#!/usr/bin/env bash
# Install the VirtualBox Guest Additions (vboxsf shared folders etc), built
# from the Guest Additions ISO against the kernel headers. Build tools and
# the headers metapackage stay installed so the modules rebuild (dkms) when
# the guest kernel is upgraded.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

case $(uname -m) in
  aarch64) installer=VBoxLinuxAdditions-arm64.run headers=linux-headers-arm64 ;;
  *)       installer=VBoxLinuxAdditions.run headers=linux-headers-amd64 ;;
esac
apt-get update
apt-get install -y --no-install-recommends build-essential dkms bzip2 \
  "linux-headers-$(uname -r)" "$headers"

mnt=$(mktemp -d)
mount -o loop,ro /tmp/VBoxGuestAdditions.iso "$mnt"
# The installer exits 2 when it cannot load modules into the running
# kernel (e.g. no X11); the modules are verified below instead.
sh "$mnt/$installer" --nox11 || [ $? -eq 2 ]
umount "$mnt"
rm -rf "$mnt" /tmp/VBoxGuestAdditions.iso

modinfo vboxsf vboxguest
usermod -aG vboxsf vagrant
