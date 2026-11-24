#!/usr/bin/env bash
# Final cleanup before the disk is packaged (runs as root, every provider).
set -euxo pipefail

# One system generation (the VirtualBox build adds one), and the boot menu
# to match; then deduplicate the store.
nix-collect-garbage -d
/run/current-system/bin/switch-to-configuration boot
nix-store --optimise
test "$(ls -d /nix/var/nix/profiles/system-*-link | wc -l)" -eq 1

# New machine-id (and DHCP client id) on first boot of every VM.
truncate -s 0 /etc/machine-id
rm -f /var/lib/systemd/random-seed
rm -rf /var/lib/systemd/network/*

# Per-VM SSH host keys: sshd makes new ones when it starts.
rm -f /etc/ssh/ssh_host_*

# Logs, temp files, shell history.
journalctl --rotate || true
journalctl --vacuum-time=1s || true
rm -rf /tmp/* /var/tmp/*
rm -f /root/.bash_history /home/vagrant/.bash_history

# Hand free blocks back to the hypervisor so the image compacts well.
# QEMU (discard=unmap) honours TRIM. VirtualBox ignores TRIM on VMDK disks,
# so there the free space is zero-filled.
if [ "${HAKO_PROVIDER:-}" = virtualbox ]; then
  for fs in / /boot; do
    dd if=/dev/zero of="$fs/ZERO" bs=4M status=none || true
    sync
    rm -f "$fs/ZERO"
  done
fi
fstrim -av || true
sync
