#!/usr/bin/env bash
# Install EndeavourOS onto the helper VM's second disk (/dev/vdb), from the
# Debian helper (runs as root). EndeavourOS is Arch Linux plus its own
# repository and tools, and EndeavourOS ARM is installed the same way on top
# of Arch Linux ARM, so:
#
#   1. unpack an Arch root file system onto the disk: Arch's bootstrap
#      tarball (x86_64, sha256 from the mirror over HTTPS) or Arch Linux
#      ARM's generic aarch64 tarball (its GnuPG signature checked against
#      the Arch Linux ARM build key);
#   2. in a chroot: the base system, kernel, sshd, sudo, systemd-networkd,
#      systemd-boot and the vagrant user;
#   3. add the [endeavouros] repository (keyring and mirror list) and the
#      EndeavourOS tools: eos-hooks (os-release), eos-update, eos-rankmirrors
#      and yay.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

disk=/dev/vdb
[ -b "$disk" ] || { echo "no second disk $disk" >&2; exit 1; }
cloud-init status --wait || true

apt-get update
apt-get install -y --no-install-recommends dosfstools e2fsprogs zstd libarchive-tools gnupg dirmngr curl ca-certificates

work=/var/tmp/hako-rootfs
mkdir -p "$work"
cd "$work"

# --- 1. Arch root file system ------------------------------------------------
case $(uname -m) in
  x86_64)
    arch=x86_64 keyring=archlinux kernel=linux image=vmlinuz-linux
    mirror='https://geo.mirror.pkgbuild.com/$repo/os/$arch'
    base=https://geo.mirror.pkgbuild.com/iso/latest
    file=$(curl -fsSL "$base/sha256sums.txt" | awk '$2 ~ /^archlinux-bootstrap-[0-9.]+-x86_64\.tar\.zst$/ { print $2 }')
    sum=$(curl -fsSL "$base/sha256sums.txt" | awk -v f="$file" '$2 == f { print $1 }')
    curl -fL --retry 3 -o rootfs.tar "$base/$file"
    echo "$sum  rootfs.tar" | sha256sum -c
    strip=1   # the tarball's files are under root.x86_64/
    source="$base/$file" ;;
  aarch64)
    arch=aarch64 keyring=archlinuxarm kernel=linux-aarch64 image=Image
    mirror='http://mirror.archlinuxarm.org/$arch/$repo'
    url=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
    curl -fL --retry 3 -o rootfs.tar "$url"
    curl -fL --retry 3 -o rootfs.tar.sig "$url.sig"
    # Arch Linux ARM Build System <builder@archlinuxarm.org>
    export GNUPGHOME=$work/gnupg
    install -d -m 0700 "$GNUPGHOME"
    # (Fetched over HTTPS with curl: GnuPG's dirmngr may find no route.)
    curl -fsSL --retry 3 'https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x68B3537F39A313B3E574D06777193F152BDBE6A6' |
      gpg --batch --import
    gpg --batch --status-fd 1 --verify rootfs.tar.sig rootfs.tar | grep -q '^\[GNUPG:\] VALIDSIG 68B3537F39A313B3E574D06777193F152BDBE6A6 '
    strip=0
    source=$url ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

# GPT: a 512 MB EFI system partition (mounted at /boot, so systemd-boot
# reads the kernels from it) and an ext4 root.
sfdisk "$disk" <<'PART'
label: gpt
size=512MiB, type=uefi, name=ESP
type=linux, name=root
PART
udevadm settle
mkfs.vfat -F 32 -n BOOT "${disk}1"
mkfs.ext4 -q -L root "${disk}2"
mnt=/mnt
mount "${disk}2" "$mnt"
# /boot is left out: the kernel is (re)installed by pacman onto the ESP.
bsdtar -xpf rootfs.tar -C "$mnt" --numeric-owner --strip-components "$strip" --exclude '*/boot/*' --exclude 'boot/*'
rm -f rootfs.tar rootfs.tar.sig
mkdir -p "$mnt/boot"
mount -o umask=0077 "${disk}1" "$mnt/boot"

# --- 2. The base system, in a chroot ---------------------------------------
mount --rbind /dev "$mnt/dev"; mount --make-rslave "$mnt/dev"
mount -t proc proc "$mnt/proc"
mount -t sysfs sys "$mnt/sys"
mount -t tmpfs tmpfs "$mnt/run"
rm -f "$mnt/etc/resolv.conf"
cp -L /etc/resolv.conf "$mnt/etc/resolv.conf"
in_root() { chroot "$mnt" /usr/bin/env -i HOME=/root TERM=dumb LANG=C.UTF-8 PATH=/usr/local/sbin:/usr/local/bin:/usr/bin "$@"; }

printf 'Server = %s\n' "$mirror" > "$mnt/etc/pacman.d/mirrorlist"
# No free-space check: pacman cannot see the mount points from the chroot.
sed -i 's/^CheckSpace/#CheckSpace/' "$mnt/etc/pacman.conf"
in_root pacman-key --init
in_root pacman-key --populate "$keyring"
in_root pacman -Syu --noconfirm
in_root pacman -S --noconfirm --needed base "$kernel" mkinitcpio openssh sudo rsync curl
# Arch Linux ARM's tarball has its own user, network config and firmware.
if in_root id alarm >/dev/null 2>&1; then in_root userdel -r alarm; fi
rm -f "$mnt"/etc/systemd/network/*.network
in_root pacman -Rns --noconfirm linux-firmware 2>/dev/null || true

# Generic initramfs (no autodetect hook), as in the Arch box: drivers for
# every hypervisor (virtio, AHCI), not just this helper VM's. One image, no
# fallback.
preset=$mnt/etc/mkinitcpio.d/$kernel.preset
sed -i -e "s/^PRESETS=.*/PRESETS=('default')/" -e '/^default_options=/d' "$preset"
echo 'default_options="-S autodetect"' >> "$preset"
rm -f "$mnt"/boot/initramfs-*-fallback.img
in_root mkinitcpio -P

# File systems by UUID, so the disk boots under any hypervisor.
root_uuid=$(blkid -s UUID -o value "${disk}2")
esp_uuid=$(blkid -s UUID -o value "${disk}1")
cat > "$mnt/etc/fstab" <<FSTAB
UUID=$root_uuid  /      ext4  rw,relatime  0 1
UUID=$esp_uuid  /boot  vfat  rw,relatime,fmask=0077,dmask=0077  0 2
FSTAB

# systemd-boot, also at the removable-media path (EFI/BOOT), so the disk
# boots without NVRAM boot entries; no menu wait. (bootctl cannot check the
# partition type from the chroot.)
in_root env SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --esp-path=/boot install --no-variables
printf 'default endeavouros.conf\ntimeout 0\neditor no\n' > "$mnt/boot/loader/loader.conf"
cat > "$mnt/boot/loader/entries/endeavouros.conf" <<ENTRY
title   EndeavourOS
linux   /$image
initrd  /initramfs-linux.img
options root=UUID=$root_uuid rw
ENTRY
ls -l "$mnt/boot" "$mnt/boot/EFI/BOOT"

# Locale, time zone, host name.
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$mnt/etc/locale.gen"
in_root locale-gen
echo 'LANG=en_US.UTF-8' > "$mnt/etc/locale.conf"
ln -sf /usr/share/zoneinfo/UTC "$mnt/etc/localtime"
echo endeavouros > "$mnt/etc/hostname"
# No desktop: boot to multi-user.target.
in_root systemctl set-default multi-user.target

# Networking: one systemd-networkd file for every ethernet NIC, and
# systemd-resolved for DNS.
install -m 0644 /tmp/hako/99-hako-ethernet.network "$mnt/etc/systemd/network/99-hako-ethernet.network"
in_root systemctl enable systemd-networkd.service systemd-resolved.service sshd.service

# sshd: no reverse DNS lookups on login; host keys made on each VM's first
# boot; and the per-VM pacman keyring (both units as in the Arch box).
install -d -m 0755 "$mnt/etc/ssh/sshd_config.d"
printf 'UseDNS no\n' > "$mnt/etc/ssh/sshd_config.d/10-hako.conf"
install -m 0644 /tmp/hako/hako-ssh-hostkeys.service /tmp/hako/hako-pacman-init.service "$mnt/etc/systemd/system/"
in_root systemctl enable hako-ssh-hostkeys.service hako-pacman-init.service

# The vagrant user: password "vagrant" (console only), Vagrant's insecure
# keys, passwordless sudo.
in_root useradd -m -G wheel -s /bin/bash -c Vagrant vagrant
echo 'vagrant:vagrant' | in_root chpasswd
install -d -m 0700 "$mnt/home/vagrant/.ssh"
install -m 0600 /home/vagrant/.ssh/authorized_keys "$mnt/home/vagrant/.ssh/authorized_keys"
in_root chown -R vagrant:vagrant /home/vagrant/.ssh
printf 'vagrant ALL=(ALL) NOPASSWD: ALL\n' > "$mnt/etc/sudoers.d/vagrant"
chmod 0440 "$mnt/etc/sudoers.d/vagrant"

# --- 3. EndeavourOS ----------------------------------------------------------
# Its keyring and mirror list come from an EndeavourOS mirror over HTTPS
# (pacman -U accepts a local package without a signature by default); every
# package after them is checked against the EndeavourOS keys.
eos_mirror=https://ftp.belnet.be/mirror/endeavouros/repo/endeavouros/$arch
curl -fsSL --retry 3 -o endeavouros.db "$eos_mirror/endeavouros.db"
for pkg in endeavouros-keyring endeavouros-mirrorlist; do
  file=$(bsdtar -xOf endeavouros.db "$pkg-[0-9]*/desc" | awk '/^%FILENAME%$/ { getline; print; exit }')
  curl -fsSL --retry 3 -o "$mnt/var/tmp/$file" "$eos_mirror/$file"
  in_root pacman -U --noconfirm "/var/tmp/$file"
  rm -f "$mnt/var/tmp/$file"
done
in_root pacman-key --populate endeavouros
# The repository goes first, as on EndeavourOS.
sed -i '0,/^\[core\]/s//[endeavouros]\nSigLevel = PackageRequired\nInclude = \/etc\/pacman.d\/endeavouros-mirrorlist\n\n[core]/' "$mnt/etc/pacman.conf"
# On arm64, keep Arch Linux ARM's generic kernel: EndeavourOS ARM's own
# (linux-eos-arm, for its supported boards) would replace it, and it leaves
# out the legacy iptables tables Docker's check-config.sh requires.
if [ "$arch" = aarch64 ]; then
  sed -i 's/^#\?IgnorePkg *=.*/IgnorePkg = linux-eos-arm linux-eos-arm-headers/' "$mnt/etc/pacman.conf"
  grep -q '^IgnorePkg = linux-eos-arm' "$mnt/etc/pacman.conf"
fi
in_root pacman -Syu --noconfirm
in_root pacman -S --noconfirm --needed eos-hooks eos-update eos-rankmirrors yay
in_root pacman -Q "$kernel"
! in_root pacman -Q linux-eos-arm 2>/dev/null
# eos-hooks brands os-release when filesystem is installed or upgraded.
in_root pacman -S --noconfirm filesystem
grep -H '^NAME=' "$mnt/usr/lib/os-release" "$mnt/etc/os-release" || true
grep -q '^NAME=.*EndeavourOS' "$mnt/etc/os-release"

# What the box was built from, for anyone inspecting a VM.
cat > "$mnt/etc/hako-release" <<REL
BOX=$HAKO_BOX
VERSION=$HAKO_VERSION
ROOTFS=$source
REL

sed -i 's/^#CheckSpace/CheckSpace/' "$mnt/etc/pacman.conf"
in_root pacman -Scc --noconfirm
ln -sf /run/systemd/resolve/stub-resolv.conf "$mnt/etc/resolv.conf"
: > "$mnt/etc/machine-id"

# pacman-key leaves gpg-agent (and dirmngr, keyboxd) running in the chroot:
# stop every process whose root is the new system.
in_root gpgconf --homedir /etc/pacman.d/gnupg --kill all || true
for proc in /proc/[0-9]*; do
  if [ "$(readlink "$proc/root" 2>/dev/null)" = "$mnt" ]; then
    echo "stopping ${proc#/proc/}: $(tr '\0' ' ' < "$proc/cmdline")"
    kill "${proc#/proc/}" 2>/dev/null || true
  fi
done
sleep 2
sync
umount -R -l "$mnt/dev"
umount "$mnt/proc" "$mnt/sys" "$mnt/run"
umount "$mnt/boot"
umount "$mnt"
sync
