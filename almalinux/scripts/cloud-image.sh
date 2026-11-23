#!/usr/bin/env bash
# Print the URL and sha256 checksum ("URL sha256:HEX") of the newest
# AlmaLinux GenericCloud image for a major version and architecture.
#
#   scripts/cloud-image.sh MAJOR(10) ARCH(arm64|amd64) [X86_LEVEL(v3|v2)]
#
# AlmaLinux builds x86_64 for x86-64-v3 (Haswell or newer), like RHEL 10,
# and also for x86-64-v2 (older x86 CPUs); X86_LEVEL=v2 picks the second.
# The dated name (AlmaLinux-10-GenericCloud-10.3-20261116.0...) says which
# point release and build the box came from, so it is read from the
# directory listing (newest version, then newest date) rather than using
# the -latest alias, and its checksum from the directory's CHECKSUM file.
# (The -ext4 images are skipped: the default image's XFS root matches RHEL.)
set -euo pipefail

major=$1 arch=$2 level=${3:-v3}
case $arch:$level in
  arm64:*)    rarch=aarch64 ;;
  amd64:v3)   rarch=x86_64 ;;
  amd64:v2)   rarch=x86_64_v2 ;;
  *) echo "unsupported arch/level $arch $level" >&2; exit 2 ;;
esac

base=https://repo.almalinux.org/almalinux/$major/cloud/$rarch/images
file=$(curl -fsSL "$base/" |
  grep -Eo "AlmaLinux-$major-GenericCloud-$major\.[0-9]+-[0-9]{8}\.[0-9]+\.$rarch\.qcow2\"" |
  tr -d '"' | sort -u | sort -t- -k4,4V -k5,5 | tail -1)
[[ -n $file ]] || { echo "no GenericCloud image for AlmaLinux $major $rarch in $base/" >&2; exit 1; }

sum=$(curl -fsSL "$base/CHECKSUM" | awk -v f="$file" '$2 == f && $1 ~ /^[0-9a-f]{64}$/ { print $1; exit }')
[[ -n $sum ]] || { echo "no sha256 for $file in $base/CHECKSUM" >&2; exit 1; }

echo "$base/$file sha256:$sum"
