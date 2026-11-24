#!/usr/bin/env bash
# Print the URL and sha256 checksum ("URL sha256:HEX") of the Fedora Cloud
# Base Generic image for a release and architecture.
#
#   scripts/cloud-image.sh RELEASE(45) ARCH(arm64|amd64)
#
# The file name carries the compose (Fedora-Cloud-Base-Generic-45-1.4...),
# so it is read from the directory listing, and its sha256 from the release's
# CHECKSUM file (BSD format: "SHA256 (file) = hex").
set -euo pipefail

release=$1 arch=$2
case $arch in arm64) rarch=aarch64 ;; amd64) rarch=x86_64 ;; *) echo "unsupported arch $arch" >&2; exit 2 ;; esac

base=https://dl.fedoraproject.org/pub/fedora/linux/releases/$release/Cloud/$rarch/images
listing=$(curl -fsSL "$base/")
file=$(printf '%s\n' "$listing" |
  grep -Eo "Fedora-Cloud-Base-Generic-$release-[0-9.]+\.$rarch\.qcow2\"" | tr -d '"' | sort -uV | tail -1)
[[ -n $file ]] || { echo "no Cloud Base Generic image for Fedora $release $rarch in $base/" >&2; exit 1; }
checksum=$(printf '%s\n' "$listing" | grep -Eo "Fedora-Cloud-$release-[0-9.]+-$rarch-CHECKSUM\"" | tr -d '"' | sort -uV | tail -1)

sum=$(curl -fsSL "$base/$checksum" | sed -n "s/^SHA256 ($file) = \([0-9a-f]\{64\}\)$/\1/p")
[[ -n $sum ]] || { echo "no sha256 for $file in $base/$checksum" >&2; exit 1; }

echo "$base/$file sha256:$sum"
