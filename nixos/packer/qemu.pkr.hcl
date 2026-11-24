# NixOS has no official cloud image, so the libvirt box is made in two steps
# with QEMU (HVF or KVM), arm64 or amd64 to match the host:
#
#   1. "installer": a helper VM booted from Debian's generic cloud image,
#      with a second, empty disk. It installs NixOS onto that disk with the
#      official installer tools (scripts/install.sh), as the NixOS manual
#      describes for installing from another Linux distribution.
#   2. "libvirt": boots the installed disk itself, checks it and cleans it
#      up; this disk is the box.

source "qemu" "installer" {
  vm_name          = "${local.vm_name}-installer.qcow2"
  output_directory = "${path.root}/../output-installer"

  # The helper's own disk is the Debian cloud image (grown to 8 GB, room for
  # the Nix store the installer tools need); the second disk is where NixOS
  # goes, and becomes the box.
  iso_url              = var.helper_image_url
  iso_checksum         = var.helper_image_checksum
  disk_image           = true
  disk_size            = "8G"
  disk_additional_size = [var.disk_size]
  format               = "qcow2"

  qemu_binary       = local.cfg.qemu_binary
  machine_type      = local.cfg.machine_type
  accelerator       = var.accelerator
  cpu_model         = "host"
  cpus              = var.cpus
  memory            = var.memory
  efi_boot          = true
  efi_firmware_code = local.efi_code_path
  efi_firmware_vars = local.efi_vars_path
  efi_drop_efivars  = true

  net_device         = "virtio-net-pci"
  disk_interface     = "virtio"
  disk_discard       = "unmap"
  disk_detect_zeroes = "unmap"
  headless           = true
  display            = "none"

  # NoCloud seed for the helper (volume label must be "cidata").
  cd_files        = ["${path.root}/../cloud-init/meta-data", "${path.root}/../cloud-init/user-data"]
  cd_label        = "cidata"
  cdrom_interface = local.cfg.cdrom_if

  communicator         = "ssh"
  ssh_username         = "vagrant"
  ssh_private_key_file = pathexpand(var.vagrant_private_key)
  ssh_timeout          = "10m"
  shutdown_command     = "sudo shutdown -P now"
}

# libvirt box (used by vagrant-qemu and vagrant-libvirt): the disk NixOS
# was installed onto, booted on its own.
source "qemu" "libvirt" {
  vm_name          = "${local.vm_name}.qcow2"
  output_directory = "${path.root}/../output-libvirt"

  iso_url          = var.installed_image
  iso_checksum     = "none"
  disk_image       = true
  skip_resize_disk = true
  format           = "qcow2"

  qemu_binary       = local.cfg.qemu_binary
  machine_type      = local.cfg.machine_type
  accelerator       = var.accelerator
  cpu_model         = "host"
  cpus              = var.cpus
  memory            = var.memory
  efi_boot          = true
  efi_firmware_code = local.efi_code_path
  efi_firmware_vars = local.efi_vars_path
  efi_drop_efivars  = true

  net_device         = "virtio-net-pci"
  disk_interface     = "virtio"
  disk_discard       = "unmap"
  disk_detect_zeroes = "unmap"
  disk_compression   = true
  headless           = true
  display            = "none"

  communicator         = "ssh"
  ssh_username         = "vagrant"
  ssh_private_key_file = pathexpand(var.vagrant_private_key)
  ssh_timeout          = "10m"
  shutdown_command     = "sudo shutdown -P now"
}
