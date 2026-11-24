#!/usr/bin/env bash
# First boot of the installed system (libvirt build): check it came up as
# configured, and record the exact NixOS version. Runs as root.
set -euxo pipefail

nixos-version
uname -a
state=$(systemctl is-system-running --wait || true)
echo "system state: $state"
if [ "$state" != running ]; then systemctl --failed --no-pager; exit 1; fi
networkctl list --no-pager
nix-channel --list

# The installer could not know the version string until the system ran.
sed -i "s/^NIXOS=.*/NIXOS=$(nixos-version)/" /etc/hako-release
cat /etc/hako-release
