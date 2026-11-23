#!/usr/bin/env bash
# Print the URL and sha256 checksum ("URL sha256:HEX") of the latest Gentoo
# cloud-init disk image for an architecture.
#
#   scripts/cloud-image.sh ARCH(arm64|amd64)
#
# Gentoo's release engineering rebuilds these images weekly and names each
# file after its build timestamp, e.g.
#   current-di-arm64-cloudinit/di-arm64-cloudinit-20261122T234603Z.qcow2
# so the name is read from latest-di-<arch>-cloudinit.txt and the checksum
# from the image's .sha256 file (both PGP clear-signed; only the payload
# lines are used).
set -euo pipefail

arch=$1
case $arch in arm64|amd64) ;; *) echo "unsupported arch $arch" >&2; exit 2 ;; esac

base=https://distfiles.gentoo.org/releases/$arch/autobuilds
latest=$(curl -fsSL "$base/latest-di-$arch-cloudinit.txt")
# Payload line: "<timestamp>/di-<arch>-cloudinit-<timestamp>.qcow2 <size>"
path=$(printf '%s\n' "$latest" | awk -v a="$arch" '$1 ~ "/di-" a "-cloudinit-.*\\.qcow2$" { print $1; exit }')
[[ -n $path ]] || { echo "no image listed in $base/latest-di-$arch-cloudinit.txt" >&2; exit 1; }

url=$base/$path
file=${path##*/}
sum=$(curl -fsSL "$url.sha256" | awk -v f="$file" '$2 == f && $1 ~ /^[0-9a-f]{64}$/ { print $1; exit }')
[[ -n $sum ]] || { echo "no sha256 for $file in $url.sha256" >&2; exit 1; }

echo "$url sha256:$sum"
