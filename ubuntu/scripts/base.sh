#!/usr/bin/env bash
# Base configuration of the box (runs as root, every provider).
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_SUSPEND=1

# Let the build-time cloud-init run finish (user creation, growpart).
cloud-init status --wait || true

# Bring the image up to date at build time; the box version is the date.
apt-get update
apt-get -y -o Dpkg::Options::=--force-confnew dist-upgrade
apt-get -y autoremove --purge

# Vagrant-friendly sshd: no reverse DNS lookups on login.
install -d -m 0755 /etc/ssh/sshd_config.d
printf 'UseDNS no\n' > /etc/ssh/sshd_config.d/10-hako.conf

# No background apt runs that grab the dpkg lock while a provisioner
# (Ansible, shell) wants it right after `vagrant up`.
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer || true
systemctl disable --now unattended-upgrades.service || true

# Networking: exactly one netplan file, matching any ethernet NIC by name.
rm -f /etc/netplan/*
install -m 0600 /tmp/hako/01-hako-netcfg.yaml /etc/netplan/01-hako-netcfg.yaml

# cloud-init: only react to a NoCloud/ConfigDrive seed (see the file).
install -m 0644 /tmp/hako/99-hako.cfg /etc/cloud/cloud.cfg.d/99-hako.cfg

# Per-VM SSH host keys, generated on first boot.
install -m 0644 /tmp/hako/hako-ssh-hostkeys.service /etc/systemd/system/hako-ssh-hostkeys.service
systemctl enable hako-ssh-hostkeys.service
