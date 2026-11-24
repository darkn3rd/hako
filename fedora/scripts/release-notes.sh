#!/usr/bin/env bash
# Print release notes listing every box in a GitHub release, by architecture.
# make publish runs this after each upload, so the notes stay right when the
# boxes are uploaded one provider at a time.
#
#   scripts/release-notes.sh REPO TAG BOX VERSION
set -euo pipefail

repo=$1 tag=$2 box=$3 version=$4

printf 'Vagrant box %s %s, built from the Fedora Cloud Base Generic image.\n\n' "$box" "$version"
printf '| Architecture | Providers |\n|---|---|\n'

# Box files are named <name>-<version>-<provider>-<arch>.box; print one row
# per architecture with its providers.
gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name' |
  sed -n 's/.*-\([a-z]*\)-\([a-z0-9]*\)\.box$/\2 \1/p' |
  LC_ALL=C sort |
  LC_ALL=C awk '
    $1 != arch { if (arch != "") print "| " arch " | " list " |"; arch = $1; list = $2; next }
               { list = list ", " $2 }
    END        { if (arch != "") print "| " arch " | " list " |" }'
