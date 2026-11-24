#!/usr/bin/env bash
# Print the URL and sha256 checksum ("URL sha256:HEX") of the newest Rocky
# Linux GenericCloud Base image for a major version and architecture.
#
#   scripts/cloud-image.sh MAJOR(10) ARCH(arm64|amd64)
#
# Rocky also publishes a Rocky-<major>-GenericCloud-Base.latest.<arch>.qcow2
# alias, but the dated name (Rocky-10-GenericCloud-Base-10.3-20261112.0...)
# says which point release and build the box came from, so it is read from
# the directory listing (newest version, then newest date) and its CHECKSUM
# file (BSD format: "SHA256 (file) = hex").
set -euo pipefail

major=$1 arch=$2
case $arch in arm64) rarch=aarch64 ;; amd64) rarch=x86_64 ;; *) echo "unsupported arch $arch" >&2; exit 2 ;; esac

base=https://dl.rockylinux.org/pub/rocky/$major/images/$rarch
file=$(curl -fsSL "$base/" |
  grep -Eo "Rocky-$major-GenericCloud-Base-$major\.[0-9]+-[0-9]{8}\.[0-9]+\.$rarch\.qcow2\"" |
  tr -d '"' | sort -u | sort -t- -k5,5V -k6,6 | tail -1)
[[ -n $file ]] || { echo "no GenericCloud Base image for Rocky $major $rarch in $base/" >&2; exit 1; }

sum=$(curl -fsSL "$base/$file.CHECKSUM" |
  sed -n "s/^SHA256 ($file) = \([0-9a-f]\{64\}\)$/\1/p")
[[ -n $sum ]] || { echo "no sha256 for $file in $base/$file.CHECKSUM" >&2; exit 1; }

echo "$base/$file sha256:$sum"
