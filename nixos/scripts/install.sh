#!/usr/bin/env bash
# Install NixOS onto the helper VM's second disk (/dev/vdb), from the Debian
# helper, as the NixOS manual describes for installing from another Linux
# distribution: Nix (Debian's package), the channel, nixos-install-tools,
# then nixos-generate-config and nixos-install. Runs as root.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

disk=/dev/vdb
[ -b "$disk" ] || { echo "no second disk $disk" >&2; exit 1; }
cloud-init status --wait || true

# Nix, with its daemon (Debian packages it), and the tools for the disk.
apt-get update
apt-get install -y --no-install-recommends nix-setup-systemd dosfstools e2fsprogs
# (The package's own setup may already be starting the socket; if starting
# it fails, show why and start the daemon itself.)
if ! systemctl start nix-daemon.socket; then
  journalctl -u nix-daemon.socket -u nix-daemon.service --no-pager | tail -20
  systemctl restart nix-daemon.service
fi
nix --version

# The channel the box follows, and the installer tools from it.
nix-channel --add "$HAKO_CHANNEL" nixos
nix-channel --update
export NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos
nix-env -f '<nixpkgs>' -iA nixos-install-tools
export PATH=/nix/var/nix/profiles/per-user/root/profile/bin:$HOME/.nix-profile/bin:$PATH

# GPT: a 512 MB EFI system partition and an ext4 root.
sfdisk "$disk" <<'PART'
label: gpt
size=512MiB, type=uefi, name=ESP
type=linux, name=nixos
PART
udevadm settle
mkfs.vfat -F 32 -n BOOT "${disk}1"
mkfs.ext4 -q -L nixos "${disk}2"
mount "${disk}2" /mnt
mkdir -p /mnt/boot
mount -o umask=077 "${disk}1" /mnt/boot

# hardware-configuration.nix (file systems by UUID, the CPU platform), then
# the box's own configuration.
nixos-generate-config --root /mnt
install -m 0644 /tmp/hako/configuration.nix /tmp/hako/hako-provider.nix /mnt/etc/nixos/
cat /mnt/etc/nixos/hardware-configuration.nix

# Install, copying the channel into the box (nixos-rebuild uses it).
nixos-install --root /mnt --no-root-passwd

# What the box was built from, for anyone inspecting a VM (firstboot.sh
# fills in the NixOS version).
cat > /mnt/etc/hako-release <<REL
BOX=$HAKO_BOX
VERSION=$HAKO_VERSION
CHANNEL=$HAKO_CHANNEL
NIXOS=unknown
REL
cat /mnt/etc/hako-release

umount -R /mnt
sync
