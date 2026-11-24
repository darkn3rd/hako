#!/usr/bin/env bash
# Wrap the finished libvirt qcow2 in a VirtualBox OVF that Packer's
# virtualbox-ovf builder can import. The NIC is an Intel 82540EM (em0):
# FreeBSD attaches no driver to VirtualBox's virtio NIC on Arm.
#
#   scripts/make-vbox-ovf.sh IMAGE.qcow2 OUTDIR ARCH(arm64|amd64)
set -euo pipefail

image=$1 outdir=$2 arch=$3
vm=hako-vbox-import-$$

case $arch in
  arm64)
    platform=arm ostype=FreeBSD_arm64 graphics=qemuramfb
    storage=(--add virtio --controller VirtIO) ;;
  amd64)
    platform=x86 ostype=FreeBSD_64 graphics=vmsvga
    storage=(--add sata --controller IntelAhci) ;;
  *) echo "unknown arch $arch" >&2; exit 2 ;;
esac
work=$(mktemp -d "${TMPDIR:-/tmp}/hako-vbox.XXXXXX")

cleanup() {
  VBoxManage unregistervm "$vm" --delete >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$outdir"
rm -f "$outdir"/*.ovf "$outdir"/*.vmdk

echo "Converting $image to VMDK"
qemu-img convert -O vmdk -o subformat=monolithicSparse "$image" "$work/disk.vmdk"

VBoxManage createvm --name "$vm" --platform-architecture "$platform" --ostype "$ostype" \
  --basefolder "$work" --register
VBoxManage modifyvm "$vm" --firmware efi --cpus 2 --memory 2048 \
  --graphicscontroller "$graphics" --vram 16 --audio-enabled off \
  --usb-xhci on --mouse usb --keyboard usb \
  --nic1 nat --nic-type1 82540EM
VBoxManage storagectl "$vm" --name Disk "${storage[@]}" --portcount 1 --bootable on
VBoxManage storageattach "$vm" --storagectl Disk --port 0 --device 0 --type hdd --medium "$work/disk.vmdk"

VBoxManage export "$vm" --output "$outdir/hako.ovf" --ovf20
ls -lh "$outdir"
