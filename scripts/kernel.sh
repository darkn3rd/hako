#!/usr/bin/env bash
# After the post-upgrade reboot: keep only the running kernel and drop the
# kernel headers (the VirtualBox build installs the headers it needs).
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_SUSPEND=1

running=$(uname -r)
old=$(dpkg-query -W -f '${Package}\n' 'linux-image-[0-9]*' 'linux-modules-[0-9]*' \
        'linux-modules-extra-[0-9]*' 2>/dev/null | grep -v -- "$running" || true)
headers=$(dpkg-query -W -f '${Package}\n' 'linux-headers-*' 2>/dev/null || true)

# linux-virtual = linux-image-virtual + linux-headers-virtual; keep only the
# image metapackage so kernel updates still arrive.
apt-get -y install linux-image-virtual
apt-get -y purge linux-virtual $old $headers || true
apt-get -y autoremove --purge
dpkg -l 'linux-image-*' | grep ^ii
