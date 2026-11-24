#!/usr/bin/env bash
# Final cleanup before the disk is packaged (runs as root, every provider).
set -euxo pipefail

apk cache clean 2>/dev/null || true
rm -rf /var/cache/apk/*

# Reset cloud-init so a VM made from the box is a new instance; drop the
# build seed and logs. Its network config described the build NIC only, so
# the box gets its own (DHCP on eth0).
cloud-init clean --logs --seed
install -m 0644 /tmp/hako/interfaces /etc/network/interfaces
rm -f /etc/network/interfaces.d/50-cloud-init* 2>/dev/null || true

# The build seed's doas rule (the box uses sudo, from /etc/sudoers.d).
rm -f /etc/doas.d/cloud-init*.conf
grep -rn vagrant /etc/doas.conf /etc/doas.d 2>/dev/null || true

# Per-VM SSH host keys: the sshd init script makes new ones on first boot.
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id 2>/dev/null || true

# Logs, temp files, shell history.
find /var/log -type f -exec truncate -s 0 {} +
rm -rf /tmp/* /var/tmp/*
rm -f /root/.ash_history /root/.bash_history /home/vagrant/.ash_history /home/vagrant/.bash_history

# Hand free blocks back to the hypervisor so the image compacts well.
# QEMU (discard=unmap) honours TRIM. VirtualBox ignores TRIM on VMDK disks,
# so there the free space is zero-filled.
if [ "${HAKO_PROVIDER:-}" = virtualbox ]; then
  for fs in / /boot; do
    mountpoint -q "$fs" || [ "$fs" = / ] || continue
    dd if=/dev/zero of="$fs/ZERO" bs=4M 2>/dev/null || true
    sync
    rm -f "$fs/ZERO"
  done
fi
fstrim -av || fstrim -v / || true
sync
