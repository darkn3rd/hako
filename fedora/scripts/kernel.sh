#!/usr/bin/env bash
# After the post-upgrade reboot: keep only the running kernel. (The cloud
# image has kernel-core but not the kernel metapackage.)
set -euxo pipefail

uname -r
# The reboot must have booted the newest installed kernel.
newest=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | sort -V | tail -1)
[ "$(uname -r)" = "$newest" ] || { echo "running $(uname -r), newest installed is $newest" >&2; exit 1; }
# Every kernel package of another version (dnf5's --oldinstallonly keeps
# up to installonly_limit kernels, so name them).
old=$(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 'kernel*' | grep -v -- "$(uname -r)" || true)
[ -z "$old" ] || dnf -y remove $old
rpm -qa 'kernel*' | sort
test "$(rpm -q kernel-core | wc -l)" -eq 1
rpm -q "kernel-modules-$(uname -r)" "kernel-modules-extra-$(uname -r)"
