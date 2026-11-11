#!/usr/bin/env bash
# Wrap the finished libvirt qcow2 in a VirtualBox (ARM) OVF that Packer's
# virtualbox-ovf builder can import.
#
#   scripts/make-vbox-ovf.sh IMAGE.qcow2 OUTDIR
set -euo pipefail

image=$1 outdir=$2
vm=hako-vbox-import-$$
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

VBoxManage createvm --name "$vm" --platform-architecture arm --ostype Ubuntu_arm64 \
  --basefolder "$work" --register
VBoxManage modifyvm "$vm" --firmware efi --cpus 2 --memory 2048 \
  --graphicscontroller qemuramfb --vram 16 --audio-enabled off \
  --usb-xhci on --mouse usb --keyboard usb \
  --nic1 nat --nic-type1 virtio
VBoxManage storagectl "$vm" --name VirtIO --add virtio --controller VirtIO --portcount 1 --bootable on
VBoxManage storageattach "$vm" --storagectl VirtIO --port 0 --device 0 --type hdd --medium "$work/disk.vmdk"

VBoxManage export "$vm" --output "$outdir/hako.ovf" --ovf20
ls -lh "$outdir"
