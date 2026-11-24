#!/usr/bin/env bash
# After the post-upgrade reboot: the newest kernel must be running, then
# only it is kept (the linux-image-<arch> metapackage stays, so kernel
# updates still arrive).
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Installed kernel image packages only (dpkg-query also lists known ones).
installed=$(dpkg-query -W -f '${Package} ${db:Status-Abbrev}\n' 'linux-image-[0-9]*' |
  awk '$2 == "ii" { print $1 }')
running=$(uname -r)
newest=$(printf '%s\n' "$installed" | sed 's/^linux-image-//' | sort -V | tail -1)
if [ "$running" != "$newest" ]; then
  echo "running kernel $running is not the newest installed ($newest)" >&2
  exit 1
fi
old=$(printf '%s\n' "$installed" | grep -vx "linux-image-$running" || true)
[ -z "$old" ] || apt-get -y purge $old
apt-get -y autoremove --purge
dpkg -l 'linux-image-*' | grep ^ii
test "$(dpkg-query -W -f '${db:Status-Abbrev}\n' 'linux-image-[0-9]*' | grep -c '^ii')" -eq 1
