#!/usr/bin/env bash
# Print the URL and sha512 checksum ("URL sha512:HEX") of the newest Alpine
# Linux cloud-init image for a release branch and architecture.
#
#   scripts/cloud-image.sh BRANCH(3.24) ARCH(arm64|amd64)
#   -> .../v3.24/releases/cloud/alpine-3.24.4-aarch64-cloudinit-r0.qcow2 sha512:<hex>
#
# The newest point release, then the newest image revision (-rN), is read
# from the directory listing; each image has a .sha512 file holding the hex.
# (The image boots with Limine, on UEFI and BIOS alike.)
set -euo pipefail

branch=$1 arch=$2
case $arch in arm64) rarch=aarch64 ;; amd64) rarch=x86_64 ;; *) echo "unsupported arch $arch" >&2; exit 2 ;; esac

base=https://dl-cdn.alpinelinux.org/alpine/v$branch/releases/cloud
file=$(curl -fsSL --retry 3 "$base/" |
  grep -Eo "\"alpine-$branch\.[0-9]+-$rarch-cloudinit-r[0-9]+\.qcow2\"" | tr -d '"' |
  sed 's/-r\([0-9]*\)\.qcow2$/ \1/' | sort -u | sort -k1,1V -k2,2n | tail -1 | sed 's/ \(.*\)$/-r\1.qcow2/')
[[ -n $file ]] || { echo "no cloud-init image for Alpine $branch $rarch in $base/" >&2; exit 1; }

sum=$(curl -fsSL --retry 3 "$base/$file.sha512" | awk '{ print $1 }')
[[ $sum =~ ^[0-9a-f]{128}$ ]] || { echo "no sha512 for $file in $base/$file.sha512" >&2; exit 1; }

echo "$base/$file sha512:$sum"
