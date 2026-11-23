#!/usr/bin/env bash
# VirtualBox guest support (vboxsf shared folders etc). Arch's kernel ships
# the vboxguest and vboxsf modules, so only the userspace tools are needed:
# no build tools, no kernel headers, nothing to rebuild on kernel upgrades.
set -euxo pipefail

pacman -Sy --noconfirm --needed virtualbox-guest-utils-nox
systemctl enable vboxservice.service

modinfo vboxsf vboxguest
usermod -aG vboxsf vagrant
