#!/usr/bin/env bash
# VirtualBox guest support. On x86_64 the Arch kernel has the vboxguest and
# vboxsf modules, and virtualbox-guest-utils-nox adds VBoxService and the
# mount helper. Linux has no VirtualBox guest modules on arm64, so there the
# box's Vagrantfile uses rsync for the shared folder.
set -euxo pipefail

case $(uname -m) in
  x86_64)
    pacman -Sy --noconfirm --needed virtualbox-guest-utils-nox
    systemctl enable vboxservice.service
    modinfo vboxsf vboxguest ;;
  *) echo "no VirtualBox guest modules on $(uname -m); synced folders use rsync" ;;
esac
