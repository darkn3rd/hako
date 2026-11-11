#!/usr/bin/env bash
# Boot a hako box with Vagrant from a catalog and check it:
#   - boot (systemd-analyze) must finish within MAX_BOOT seconds
#   - SSH works, sudo is passwordless, exactly one netplan file, no failed
#     units, and the VM comes back after a reboot
# then destroy the VM.
#
#   scripts/test-box.sh PROVIDER(libvirt|virtualbox) CATALOG_URL VERSION
set -euo pipefail

provider=$1 catalog_url=$2 version=$3
max_boot=${MAX_BOOT:-15}
here=$(cd "$(dirname "$0")/.." && pwd)

case $provider in
  libvirt)    vagrant_provider=qemu ;;
  virtualbox) vagrant_provider=virtualbox ;;
  *) echo "unknown provider $provider" >&2; exit 2 ;;
esac

workdir=$(mktemp -d "${TMPDIR:-/tmp}/hako-test.XXXXXX")
trap 'cd "$workdir" && vagrant destroy -f >/dev/null 2>&1 || true; rm -rf "$workdir"' EXIT

# A rebuilt box keeps its version number, so drop any cached copy first.
# (No --architecture: Vagrant 2.4.9 then claims arm64 is not installed.)
if vagrant box list | grep -q "^hako/ubuntu-26.04 *($provider, $version"; then
  vagrant box remove hako/ubuntu-26.04 --box-version "$version" \
    --provider "$provider" --force
fi

cat > "$workdir/Vagrantfile" <<VF
Vagrant.configure("2") do |config|
  config.vm.box         = "hako/ubuntu-26.04"
  config.vm.box_url     = "$catalog_url"
  config.vm.box_version = "$version"
  if "$provider" == "virtualbox"
    # Checks the Guest Additions (vboxsf).
    config.vm.synced_folder ".", "/vagrant", type: "virtualbox"
  else
    config.vm.synced_folder ".", "/vagrant", disabled: true
  end
  config.vm.provider "qemu" do |qe|
    qe.ssh_auto_correct = true
  end
end
VF

cd "$workdir"
start=$(date +%s)
vagrant up --provider "$vagrant_provider"
echo "vagrant up took $(( $(date +%s) - start ))s"

# Wait until systemd reports the boot as finished.
for _ in $(seq 1 30); do
  if out=$(vagrant ssh -c 'systemd-analyze time' 2>/dev/null); then break; fi
  sleep 2
done
echo "$out"
total=$(printf '%s\n' "$out" | sed -n 's/.*= \(.*\)$/\1/p' | head -1)
seconds=$(printf '%s\n' "$total" | awk '{
  s = 0
  for (i = 1; i <= NF; i++) {
    v = $i
    if (v ~ /ms$/)       { sub(/ms$/, "", v); s += v / 1000 }
    else if (v ~ /min$/) { sub(/min$/, "", v); s += v * 60 }
    else if (v ~ /s$/)   { sub(/s$/, "", v); s += v }
  }
  printf "%.1f", s }')
echo "boot time: ${seconds}s (limit ${max_boot}s)"

vagrant ssh -c 'set -e
  echo "hostname: $(hostname)  kernel: $(uname -r)"
  sudo -n true && echo "passwordless sudo: ok"
  ls /etc/netplan; test "$(ls /etc/netplan | wc -l)" -eq 1
  state=$(systemctl is-system-running --wait || true)
  echo "system state: $state"
  if [ "$state" != running ]; then systemctl --failed --no-pager; exit 1; fi
  systemd-analyze blame | head -5'

if [[ $provider == virtualbox ]]; then
  vagrant ssh -c 'set -e; mount -t vboxsf; test -f /vagrant/Vagrantfile && echo "vboxsf shared folder: ok"'
fi

# A second boot must work too (no first-boot-only luck).
vagrant reload
vagrant ssh -c 'systemctl is-system-running --wait && uptime'

if awk -v s="$seconds" -v m="$max_boot" 'BEGIN { exit !(s > m) }'; then
  echo "FAIL: boot took ${seconds}s, over ${max_boot}s" >&2
  exit 1
fi
echo "PASS: hako/ubuntu-26.04 $version ($provider)"
