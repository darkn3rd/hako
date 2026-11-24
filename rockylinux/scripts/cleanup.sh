#!/usr/bin/env bash
# Final cleanup before the disk is packaged (runs as root, every provider).
set -euxo pipefail

dnf -y autoremove
dnf clean all
rm -rf /var/cache/dnf/*

# Reset cloud-init so a VM made from the box is a new instance; drop the
# build seed and logs, and the connection the build seed generated.
cloud-init clean --logs --seed
rm -f /etc/NetworkManager/system-connections/cloud-init-*.nmconnection
rm -f /etc/NetworkManager/conf.d/30-cloud-init-*.conf
rm -f /etc/sysconfig/network-scripts/ifcfg-*
# No connection profiles remain (see base.sh).
ls -la /etc/NetworkManager/system-connections
test -z "$(ls /etc/NetworkManager/system-connections)"

# New machine-id (and DHCP client id) on first boot of every VM.
truncate -s 0 /etc/machine-id
rm -f /var/lib/systemd/random-seed
rm -rf /var/lib/NetworkManager/*

# Per-VM SSH host keys: sshd-keygen@.service makes new ones on first boot.
rm -f /etc/ssh/ssh_host_*

# Logs, caches, temp files, shell history.
journalctl --rotate || true
journalctl --vacuum-time=1s || true
find /var/log -type f -exec truncate -s 0 {} +
rm -rf /tmp/* /var/tmp/*
rm -f /root/.bash_history /home/vagrant/.bash_history

# Hand free blocks back to the hypervisor so the image compacts well.
# QEMU (discard=unmap) honours TRIM. VirtualBox ignores TRIM on VMDK disks,
# so there the free space is zero-filled (only the VirtualBox build has the
# Guest Additions).
if compgen -G '/opt/VBoxGuestAdditions-*' >/dev/null; then
  for fs in / /boot /boot/efi; do
    mountpoint -q "$fs" || [[ $fs == / ]] || continue
    dd if=/dev/zero of="$fs/ZERO" bs=4M status=none || true
    sync
    rm -f "$fs/ZERO"
  done
fi
fstrim -av || true
sync
