#!/usr/bin/env bash
# Boot a hako box with Vagrant from a catalog and check it:
#   - sshd must be started within MAX_BOOT seconds of the kernel booting
#   - SSH works, sudo is passwordless, DHCP on every NIC, the rsync shared
#     folder, VBoxService on amd64 VirtualBox, and the VM comes back after a
#     reboot
# then destroy the VM.
#
#   scripts/test-box.sh PROVIDER(libvirt|virtualbox) CATALOG_URL VERSION
set -euo pipefail

box=hako/freebsd-15.1

provider=$1 catalog_url=$2 version=$3
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

cat > "$workdir/Vagrantfile" <<VF
Vagrant.configure("2") do |config|
  config.vm.box         = "$box"
  config.vm.box_url     = "$catalog_url"
  config.vm.box_version = "$version"
  # The box's default: rsync (no VirtualBox shared folders on FreeBSD).
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

# No systemd-analyze: take the time from kern.boottime to sshd's start.
seconds=$(vagrant ssh -c 'now=$(date +%s)
  boot=$(sysctl -n kern.boottime | sed "s/^{ sec = \([0-9]*\),.*/\1/")
  up=$(ps -o etimes= -p "$(cat /var/run/sshd.pid)" | tr -d " ")
  echo "$((now - up - boot)).0"' 2>/dev/null | tr -d '\r')
if [[ ! $seconds =~ ^[0-9]+\.0$ ]]; then
  echo "FAIL: could not read when sshd started ($seconds)" >&2
  exit 1
fi
echo "boot time (kernel to sshd): ${seconds}s (limit ${max_boot}s)"

vagrant ssh -c 'set -e
  echo "hostname: $(uname -n)  kernel: $(uname -r)"
  sudo -n true && echo "passwordless sudo: ok"
  freebsd-version -kru
  cat /etc/hako-release
  test "$(sysrc -n ifconfig_DEFAULT)" = DHCP && echo "DHCP on every NIC"
  ifconfig -l
  test -s /etc/hostid && echo "hostid: $(cat /etc/hostid)"
  service sshd status
  test -f /vagrant/Vagrantfile && echo "rsync shared folder: ok"'

if [[ $provider == virtualbox && $(uname -m) == x86_64 ]]; then
  vagrant ssh -c 'sudo service vboxservice status'
fi

# A second boot must work too (no first-boot-only luck).
vagrant reload
vagrant ssh -c 'service sshd status && uptime'

if awk -v s="$seconds" -v m="$max_boot" 'BEGIN { exit !(s > m) }'; then
  echo "FAIL: boot took ${seconds}s, over ${max_boot}s" >&2
  exit 1
fi
echo "PASS: $box $version ($provider)"
