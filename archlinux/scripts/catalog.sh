#!/usr/bin/env bash
# Add or update one provider entry in a Vagrant box catalog (metadata JSON).
#
#   scripts/catalog.sh CATALOG NAME VERSION PROVIDER ARCH BOX_FILE URL
#
# Creates CATALOG if missing. The version entry is created if needed (newest
# version first) and the provider entry for PROVIDER+ARCH is replaced, with
# the sha256 of BOX_FILE. Per provider, amd64 is marked default_architecture
# when the version has it; a version with a single architecture marks that one.
set -euo pipefail

catalog=$1 name=$2 version=$3 provider=$4 arch=$5 box=$6 url=$7

[[ -f $box ]] || { echo "no such box: $box" >&2; exit 1; }
checksum=$(shasum -a 256 "$box" | awk '{print $1}')

[[ -f $catalog ]] || printf '{"name": "%s", "versions": []}\n' "$name" > "$catalog"

tmp=$(mktemp)
jq --arg name "$name" --arg v "$version" --arg p "$provider" --arg a "$arch" \
   --arg url "$url" --arg sum "$checksum" '
  .name = $name
  | if any(.versions[]; .version == $v) then . else .versions += [{version: $v, providers: []}] end
  | .versions |= map(
      if .version == $v then
        .providers = ([.providers[] | select((.name == $p and .architecture == $a) | not)]
          + [{name: $p, architecture: $a, default_architecture: true,
              url: $url, checksum_type: "sha256", checksum: $sum}]
          | group_by(.name)
          | map((any(.[]; .architecture == "amd64")) as $amd64
                | map(.default_architecture = (($amd64 | not) or .architecture == "amd64")))
          | add | sort_by(.name, .architecture))
      else . end)
  | .versions |= sort_by(.version | split(".") | map(tonumber)) | .versions |= reverse
' "$catalog" > "$tmp"
mv "$tmp" "$catalog"
echo "$catalog: $name $version $provider/$arch sha256=$checksum"
