#!/usr/bin/env bash
# Boot a hako box with Vagrant from a catalog and check it:
#   - sshd must be started within MAX_BOOT seconds of the kernel starting
#   - SSH works, sudo is passwordless, the box's own network config, one
#     kernel, no crashed OpenRC services, the shared folder (vboxsf on x86
#     VirtualBox, rsync on arm64 VirtualBox), and the VM comes back after a
#     reboot
#   - the kernel passes Moby's check-config.sh (containers can run) and
#     Docker's kernel modules load (Docker itself is not installed)
# then destroy the VM.
#
#   scripts/test-box.sh PROVIDER(libvirt|virtualbox) CATALOG_URL VERSION
set -euo pipefail

box=hako/alpine-3.24

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

# OpenRC has no systemd-analyze: take the time from kernel start to sshd's
# start (field 22 of /proc/PID/stat, in clock ticks since boot).
seconds=$(vagrant ssh -c 'pid=$(cat /run/sshd.pid); awk -v hz="$(getconf CLK_TCK)" "{ printf \"%.1f\", \$22 / hz }" /proc/$pid/stat' 2>/dev/null | tr -d '\r')
if [[ ! $seconds =~ ^[0-9]+\.[0-9]$ ]]; then
  echo "FAIL: could not read when sshd started ($seconds)" >&2
  exit 1
fi
echo "boot time (kernel start to sshd): ${seconds}s (limit ${max_boot}s)"

vagrant ssh -c 'set -e
  echo "hostname: $(uname -n)  kernel: $(uname -r)"
  sudo -n true && echo "passwordless sudo: ok"
  cat /etc/alpine-release /etc/hako-release
  # The box'"'"'s own network config: DHCP on eth0 (Vagrant may append).
  grep -q "^iface eth0 inet dhcp" /etc/network/interfaces
  ip -4 -br addr show eth0
  test "$(apk info -e linux-virt linux-lts linux-edge | wc -l)" -eq 1 && echo "one kernel: $(uname -r)"
  crashed=$(sudo rc-status --crashed || true)
  if [ -n "$crashed" ]; then echo "FAIL: crashed services: $crashed" >&2; exit 1; fi
  rc-status default'

if [[ $provider == virtualbox ]]; then
  if [[ $(uname -m) == x86_64 ]]; then
    vagrant ssh -c 'set -e; mount -t vboxsf; test -f /vagrant/Vagrantfile && echo "vboxsf shared folder: ok"'
  else
    vagrant ssh -c 'set -e; test -f /vagrant/Vagrantfile && echo "rsync shared folder: ok"'
  fi
fi

# A second boot must work too (no first-boot-only luck).
vagrant reload
vagrant ssh -c 'test -z "$(sudo rc-status --crashed || true)" && uptime'

# Containers: every kernel feature Docker requires must be configured
# (Moby's check-config.sh exits non-zero otherwise), and the modules must
# really be on disk (check-config only reads the kernel config).
vagrant upload "$check_config" /tmp/check-config.sh
# (Alpine has no zgrep, and BusyBox zcat only reads compressed files, so
# check-config.sh gets a gzipped copy of /boot/config-<version>.)
vagrant ssh -c 'sudo gzip -c "/boot/config-$(uname -r)" > /tmp/config.gz && sudo NO_COLOR=1 sh /tmp/check-config.sh /tmp/config.gz'
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
