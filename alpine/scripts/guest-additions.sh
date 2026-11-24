#!/usr/bin/env bash
# VirtualBox guest support. Alpine's kernel has the vboxguest and vboxsf
# modules on x86_64 (mainline Linux builds them only for x86), which is all
# Vagrant needs to mount a shared folder; the Guest Additions ISO's
# installer needs glibc, so it is not used. VBoxService (time sync, guest
# properties) comes from Alpine's virtualbox-guest-additions package. On
# arm64 there are no guest modules: the box's Vagrantfile uses rsync for
# the shared folder there.
set -euxo pipefail
rm -f /tmp/VBoxGuestAdditions.iso

case $(uname -m) in
  x86_64)
    modinfo vboxguest vboxsf
    apk add virtualbox-guest-additions
    rc-update add virtualbox-guest-additions default
    printf 'vboxsf\n' > /etc/modules-load.d/hako-vboxsf.conf ;;
  *) echo "no VirtualBox guest modules on $(uname -m); synced folders use rsync" ;;
esac
