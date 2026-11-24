#!/bin/sh
# VirtualBox guest support: VBoxService and the guest driver from the
# virtualbox-ose-additions package (time sync, guest properties, clean
# shutdown). It is built for amd64 only; Vagrant has no VirtualBox shared
# folder support for FreeBSD either way, so the box uses rsync for that.
set -eux
export ASSUME_ALWAYS_YES=yes

case $(uname -m) in
  amd64)
    pkg install -y virtualbox-ose-additions-nox11
    sysrc vboxguest_enable=YES vboxservice_enable=YES ;;
  *) echo "no VirtualBox guest additions for $(uname -m)" ;;
esac
