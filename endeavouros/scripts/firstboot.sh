#!/usr/bin/env bash
# First boot of the installed system (libvirt build): check it came up as
# configured. Runs as root.
set -euxo pipefail

cat /etc/os-release
uname -a
state=$(systemctl is-system-running --wait || true)
echo "system state: $state"
if [ "$state" != running ]; then systemctl --failed --no-pager; exit 1; fi
networkctl list --no-pager
# The per-VM pacman keyring was created, and the repositories work.
test -f /etc/pacman.d/gnupg/trustdb.gpg
pacman -Sy
pacman -Q eos-hooks eos-update yay
