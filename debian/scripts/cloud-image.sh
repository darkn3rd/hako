#!/usr/bin/env bash
# Print the URL and checksum of the newest Debian "generic" cloud image for
# a release and architecture, from its dated build directory:
#
#   scripts/cloud-image.sh 13 arm64
#   -> https://cloud.debian.org/images/cloud/trixie/<date>-<n>/debian-13-generic-arm64-<date>-<n>.qcow2 sha512:<hex>
#
# The "generic" image has Debian's full kernel (AHCI, VirtualBox and other
# hardware drivers); "genericcloud" leaves those out.
set -euo pipefail

major=$1 arch=$2
case $major in
  13) codename=trixie ;;
  14) codename=forky ;;
  *) echo "unknown Debian release $major" >&2; exit 2 ;;
esac
case $arch in arm64|amd64) ;; *) echo "unknown arch $arch" >&2; exit 2 ;; esac

base=https://cloud.debian.org/images/cloud/$codename
build=$(curl -fsSL "$base/" | grep -o 'href="[0-9]\{8\}-[0-9]*/"' | sed 's/href="//; s/\/"//' |
  LC_ALL=C sort -t- -k1,1n -k2,2n | tail -1)
[ -n "$build" ] || { echo "no dated builds under $base/" >&2; exit 1; }

file=debian-$major-generic-$arch-$build.qcow2
sum=$(curl -fsSL "$base/$build/SHA512SUMS" | awk -v f="$file" '$2 == f { print $1 }')
[ -n "$sum" ] || { echo "no SHA512 for $file in $base/$build/SHA512SUMS" >&2; exit 1; }
echo "$base/$build/$file sha512:$sum"
