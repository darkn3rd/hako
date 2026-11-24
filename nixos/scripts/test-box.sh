#!/usr/bin/env bash
# Boot a hako box with Vagrant from a catalog and check it:
#   - boot (systemd-analyze) must finish within MAX_BOOT seconds
#   - SSH works, sudo is passwordless, NixOS with one system generation and
#     its channel, systemd-networkd up, no failed units, the shared folder
#     (vboxsf on x86 VirtualBox, rsync on arm64 VirtualBox), and the VM comes
#     back after a reboot
#   - the kernel passes Moby's check-config.sh (containers can run) and
#     Docker's kernel modules load (Docker itself is not installed)
# then destroy the VM.
#
#   scripts/test-box.sh PROVIDER(libvirt|virtualbox) CATALOG_URL VERSION
set -euo pipefail

box=hako/nixos-26.05

provider=$1 catalog_url=$2 version=$3
# Vendored from moby/moby (see third_party/moby/README.md).
check_config=$(cd "$(dirname "$0")/../../third_party/moby" && pwd)/check-config.sh
max_boot=${MAX_BOOT:-15}

case $provider in
  # vagrant-qemu on macOS, vagrant-libvirt on Linux (set by the Makefile).
  libvirt)    vagrant_provider=${LIBVIRT_VAGRANT:-qemu} ;;
  virtualbox) vagrant_provider=virtualbox ;;
  *) echo "unknown provider $provider" >&2; exit 2 ;;
esac

# vagrant-libvirt talks to the system libvirtd: check access up front.
libvirt_uri=${LIBVIRT_DEFAULT_URI:-qemu:///system}
if [[ $vagrant_provider == libvirt ]] && ! virsh -c "$libvirt_uri" uri >/dev/null 2>&1; then
  echo "FAIL: cannot connect to libvirt ($libvirt_uri). Join the libvirt group and" >&2
  echo "      log in again (or run: sg libvirt -c 'make test ...')." >&2
  exit 1
fi

workdir=$(mktemp -d "${TMPDIR:-/tmp}/hako-test.XXXXXX")
trap 'cd "$workdir" && vagrant destroy -f >/dev/null 2>&1 || true; rm -rf "$workdir"' EXIT

# Run every Vagrant command from the scratch dir: Vagrant loads the first
# Vagrantfile it finds walking up from the current directory, so running from
# the repo can pick up an unrelated one in a parent directory.
cd "$workdir"

# A rebuilt box keeps its version number, so drop any cached copy first.
# (No --architecture: Vagrant 2.4.9 then claims the architecture is not
# installed, on arm64 and on amd64 alike.)
if vagrant box list | grep -q "^$box *($provider, $version"; then
  vagrant box remove "$box" --box-version "$version" \
    --provider "$provider" --force
fi

# vagrant-libvirt copies the box disk into a libvirt storage pool and reuses
# that copy for as long as it exists; vagrant box remove leaves it behind. A
# rebuilt box keeps its version, so delete the copy or the old build is tested.
if [[ $vagrant_provider == libvirt ]]; then
  vol_prefix="${box//\//-VAGRANTSLASH-}_vagrant_box_image_${version}_"
  # (virsh 8.0 vol-list has no --name; take the first column of the table.)
  { virsh -c "$libvirt_uri" vol-list default | awk 'NR > 2 && NF { print $1 }' |
      grep -F "$vol_prefix" || true; } |
    while read -r vol; do
      echo "Deleting stale libvirt volume $vol"
      virsh -c "$libvirt_uri" vol-delete "$vol" --pool default
    done
fi

# VirtualBox shared folder type: vboxsf where Linux has the guest modules.
if [[ $(uname -m) == x86_64 ]]; then vbox_sync=virtualbox; else vbox_sync=rsync; fi

cat > "$workdir/Vagrantfile" <<VF
Vagrant.configure("2") do |config|
  config.vm.box         = "$box"
  config.vm.box_url     = "$catalog_url"
  config.vm.box_version = "$version"
  if "$provider" == "virtualbox"
    # Checks the shared folder (vboxsf on x86; the box uses rsync on arm64).
    config.vm.synced_folder ".", "/vagrant", type: "$vbox_sync"
  else
    config.vm.synced_folder ".", "/vagrant", disabled: true
  end
  config.vm.provider "qemu" do |qe|
    qe.ssh_auto_correct = true
  end
  # vagrant-libvirt defaults to 512 MB.
  config.vm.provider "libvirt" do |lv|
    lv.memory = 2048
    lv.cpus   = 2
  end
end
VF

start=$(date +%s)
vagrant up --provider "$vagrant_provider"
echo "vagrant up took $(( $(date +%s) - start ))s"

# Wait until systemd reports the boot as finished.
for _ in $(seq 1 30); do
  if out=$(vagrant ssh -c 'systemd-analyze time' 2>/dev/null); then break; fi
  sleep 2
done
echo "$out"
# Kernel, initrd and userspace only: systemd-boot also reports the time spent
# in the firmware and boot loader, which GRUB-booted boxes never count.
total=$(printf '%s\n' "$out" | sed -n 's/^Startup finished in \(.*\) = .*$/\1/p' | head -1)
# LC_ALL=C: gawk 5.4.0 with no locale set never matches /s$/, which made this
# parse silently return 0.0.
seconds=$(printf '%s\n' "$total" | LC_ALL=C awk -F ' [+] ' '{
  s = 0
  for (i = 1; i <= NF; i++) {
    if ($i ~ /\((firmware|loader)\)/) continue
    n = split($i, w, " ")
    for (j = 1; j <= n; j++) {
      v = w[j]
      if (v ~ /ms$/)       { sub(/ms$/, "", v); s += v / 1000 }
      else if (v ~ /min$/) { sub(/min$/, "", v); s += v * 60 }
      else if (v ~ /s$/)   { sub(/s$/, "", v); s += v }
    }
  }
  printf "%.1f", s }')
if [[ -z $total || $seconds == 0.0 ]]; then
  echo "FAIL: could not read the boot time from systemd-analyze" >&2
  exit 1
fi
echo "boot time: ${seconds}s (limit ${max_boot}s)"

vagrant ssh -c 'set -e
  echo "hostname: $(uname -n)  kernel: $(uname -r)"
  sudo -n true && echo "passwordless sudo: ok"
  cat /etc/hako-release
  nixos-version
  test -e /etc/NIXOS
  test "$(ls -d /nix/var/nix/profiles/system-*-link | wc -l)" -eq 1 && echo "one system generation"
  sudo nix-channel --list | grep -q "^nixos " && echo "channel: $(sudo nix-channel --list)"
  networkctl list --no-pager
  state=$(systemctl is-system-running --wait || true)
  echo "system state: $state"
  if [ "$state" != running ]; then systemctl --failed --no-pager; exit 1; fi
  systemd-analyze blame | head -5'

if [[ $provider == virtualbox ]]; then
  if [[ $vbox_sync == virtualbox ]]; then
    vagrant ssh -c 'set -e; mount -t vboxsf; test -f /vagrant/Vagrantfile && echo "vboxsf shared folder: ok"'
  else
    vagrant ssh -c 'set -e; test -f /vagrant/Vagrantfile && echo "rsync shared folder: ok"'
  fi
fi

# A second boot must work too (no first-boot-only luck).
vagrant reload
vagrant ssh -c 'systemctl is-system-running --wait && uptime'

# Containers: every kernel feature Docker requires must be configured
# (Moby's check-config.sh exits non-zero otherwise), and the modules must
# really be on disk (check-config only reads the kernel config).
vagrant upload "$check_config" /tmp/check-config.sh
vagrant ssh -c 'sudo NO_COLOR=1 sh /tmp/check-config.sh'
vagrant ssh -c 'set -e
  for m in overlay veth bridge br_netfilter nf_nat nf_conntrack nf_tables nft_compat \
           xt_conntrack xt_addrtype xt_MASQUERADE xt_mark ip_tables iptable_filter \
           iptable_nat ip6_tables ip6table_filter ip6table_nat; do
    sudo modprobe "$m" || { echo "FAIL: cannot load kernel module $m" >&2; exit 1; }
  done
  echo "docker kernel modules: ok"'

if awk -v s="$seconds" -v m="$max_boot" 'BEGIN { exit !(s > m) }'; then
  echo "FAIL: boot took ${seconds}s, over ${max_boot}s" >&2
  exit 1
fi
echo "PASS: $box $version ($provider)"
