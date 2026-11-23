#!/usr/bin/env bash
# Install the VirtualBox Guest Additions (vboxsf shared folders etc).
# Build tools and kernel headers stay installed so the modules rebuild when
# the guest kernel is upgraded.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_SUSPEND=1

apt-get update
apt-get install -y --no-install-recommends build-essential dkms bzip2 \
  "linux-headers-$(uname -r)" linux-headers-generic

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
