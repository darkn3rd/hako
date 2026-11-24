#!/usr/bin/env bash
# VirtualBox guest support, from NixOS itself: on x86_64 the box enables
# virtualisation.virtualbox.guest (vboxguest, vboxsf, VBoxService) in
# hako-provider.nix and rebuilds. Linux has no VirtualBox guest modules on
# arm64, so there the box's Vagrantfile uses rsync for the shared folder.
set -euxo pipefail

case $(uname -m) in
  x86_64)
    cat > /etc/nixos/hako-provider.nix <<'NIX'
# What differs between the hako libvirt and VirtualBox boxes
# (/etc/nixos/hako-provider.nix). This is the VirtualBox box.
{ ... }:

{
  virtualisation.virtualbox.guest.enable = true;
}
NIX
    nixos-rebuild switch
    modinfo vboxsf vboxguest ;;
  *) echo "no VirtualBox guest modules on $(uname -m); synced folders use rsync" ;;
esac
