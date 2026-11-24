#!/usr/bin/env bash
# Download FreeBSD's BASIC-CLOUDINIT (UFS) VM image for a release and
# architecture, check its sha256, unpack it, and print the local qcow2 path
# and the URL it came from ("PATH URL").
#
#   scripts/cloud-image.sh RELEASE(15.1) ARCH(arm64|amd64) CACHE_DIR
#
# FreeBSD publishes the images xz-compressed, which Packer cannot read, so
# the unpacked image is kept in CACHE_DIR and reused while its xz matches.
set -euo pipefail

release=$1 arch=$2 cache=$3
case $arch in arm64) farch=arm64-aarch64 dir=aarch64 ;; amd64) farch=amd64 dir=amd64 ;; *) echo "unsupported arch $arch" >&2; exit 2 ;; esac

base=https://download.freebsd.org/releases/VM-IMAGES/$release-RELEASE/$dir/Latest
xzfile=FreeBSD-$release-RELEASE-$farch-BASIC-CLOUDINIT-ufs.qcow2.xz
sum=$(curl -fsSL --retry 3 "$base/CHECKSUM.SHA256" | sed -n "s/^SHA256 ($xzfile) = \([0-9a-f]\{64\}\)$/\1/p")
[[ -n $sum ]] || { echo "no sha256 for $xzfile in $base/CHECKSUM.SHA256" >&2; exit 1; }

mkdir -p "$cache"
qcow2=$cache/${xzfile%.xz}
if [[ -f $qcow2 && $(cat "$qcow2.xz-sha256" 2>/dev/null) == "$sum" ]]; then
  echo "$qcow2 $base/$xzfile"; exit 0
fi
echo "downloading $base/$xzfile" >&2
curl -fL --retry 3 -o "$cache/$xzfile" "$base/$xzfile" >&2
got=$(shasum -a 256 "$cache/$xzfile" | awk '{ print $1 }')
[[ $got == "$sum" ]] || { echo "sha256 mismatch for $xzfile: $got, expected $sum" >&2; rm -f "$cache/$xzfile"; exit 1; }
xz -d -f "$cache/$xzfile"
echo "$sum" > "$qcow2.xz-sha256"
echo "$qcow2 $base/$xzfile"
