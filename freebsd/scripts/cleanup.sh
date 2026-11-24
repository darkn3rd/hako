#!/bin/sh
# Final cleanup before the disk is packaged (runs as root, every provider).
set -eux
export ASSUME_ALWAYS_YES=yes

pkg autoremove -y
pkg clean -ay
rm -rf /var/db/freebsd-update/* /var/cache/pkg/*

# No /firstboot: the image's first-boot jobs (nuageinit, pkg bootstrap,
# growfs) already ran during the build. Drop anything nuageinit wrote for
# the build NIC.
rm -f /firstboot
grep -l 'ifconfig_vtnet' /etc/rc.conf /etc/rc.conf.d/* 2>/dev/null || true
sed -i '' '/^ifconfig_vtnet/d' /etc/rc.conf

# Per-VM identity: SSH host keys (the sshd rc script makes new ones), host
# id and machine id (made at boot when missing).
rm -f /etc/ssh/ssh_host_* /etc/hostid /etc/machine-id

# Logs, temp files, shell history.
find /var/log -type f -exec truncate -s 0 {} +
rm -rf /tmp/* /var/tmp/*
rm -f /root/.sh_history /home/vagrant/.sh_history

# Hand free blocks back to the hypervisor so the image compacts well: zero
# the free space (QEMU's detect-zeroes=unmap turns the zeros into holes;
# VirtualBox's exported VMDK skips them).
dd if=/dev/zero of=/ZERO bs=1m 2>/dev/null || true
sync
rm -f /ZERO
sync
