#!/usr/bin/env bash
# After the post-upgrade reboot: keep only the running kernel. (The cloud
# image has kernel-core but not the kernel metapackage.)
set -euxo pipefail

uname -r
dnf -y remove --oldinstallonly || true   # exits non-zero when there is nothing to remove
rpm -qa 'kernel*' | sort
test "$(rpm -q kernel-core | wc -l)" -eq 1
rpm -q "kernel-modules-extra-$(uname -r)"
