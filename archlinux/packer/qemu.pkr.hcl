# libvirt box (used by vagrant-qemu and vagrant-libvirt), built from
# the arch-boxes cloud image with QEMU (HVF or KVM), x86_64 only
source "qemu" "libvirt" {
  vm_name          = "${local.vm_name}.qcow2"
  output_directory = "${path.root}/../output-libvirt"

  # The cloud image *is* the disk; Packer copies it and grows it.
  iso_url      = local.cloud_image_url
  iso_checksum = local.cloud_image_checksum
  disk_image   = true
  disk_size    = var.disk_size
  format       = "qcow2"

  qemu_binary  = local.cfg.qemu_binary
  machine_type = local.cfg.machine_type
  accelerator  = var.accelerator
  cpu_model    = "host"
  cpus         = var.cpus
  memory       = var.memory
  efi_boot          = true
  efi_firmware_code = "${var.qemu_share_dir}/${local.cfg.efi_code}"
  efi_firmware_vars = "${var.qemu_share_dir}/${local.cfg.efi_vars}"
  efi_drop_efivars  = true

  net_device       = "virtio-net-pci"
  disk_interface   = "virtio"
  disk_discard     = "unmap"
  disk_detect_zeroes = "unmap"
  disk_compression = true
  headless         = true
  display          = "none"

  # NoCloud seed for the build only (volume label must be "cidata").
  cd_files        = ["${path.root}/../cloud-init/meta-data", "${path.root}/../cloud-init/user-data"]
  cd_label        = "cidata"
  cdrom_interface = local.cfg.cdrom_if

  communicator         = "ssh"
  ssh_username         = "vagrant"
  ssh_private_key_file = pathexpand(var.vagrant_private_key)
  ssh_timeout          = "10m"
  shutdown_command     = "sudo shutdown -P now"
}
