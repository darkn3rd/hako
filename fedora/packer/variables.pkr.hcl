variable "box_version" {
  type        = string
  description = "Date-based box version, e.g. 2026.11.22."
}

variable "os_version" {
  type        = string
  description = "Fedora release."
  default     = "45"
}

variable "arch" {
  type        = string
  description = "Guest architecture, matching the build host: arm64 or amd64."
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "amd64"], var.arch)
    error_message = "The arch must be arm64 or amd64."
  }
}

# The Makefile looks up the release's Cloud Base Generic image and its
# checksum (scripts/cloud-image.sh).
variable "cloud_image_url" {
  type        = string
  description = "Fedora Cloud Base Generic image (Fedora-Cloud-Base-Generic-45-<compose>.<arch>.qcow2)."
}

variable "cloud_image_checksum" {
  type        = string
  description = "Checksum of the image, e.g. sha256:<hex>."
}

variable "accelerator" {
  type        = string
  description = "QEMU accelerator: hvf on a Mac, kvm on Linux."
  default     = "hvf"
}

variable "qemu_share_dir" {
  type        = string
  description = "QEMU data dir holding the edk2 firmware (Homebrew: $(brew --prefix)/share/qemu)."
  default     = "/opt/homebrew/share/qemu"
}

# Full paths to the UEFI firmware, for hosts whose QEMU does not ship the
# edk2-*.fd files (Debian/Ubuntu amd64: /usr/share/OVMF/OVMF_CODE_4M.fd and
# OVMF_VARS_4M.fd). Empty means qemu_share_dir plus the edk2 file names.
variable "efi_code" {
  type    = string
  default = ""
}

variable "efi_vars" {
  type    = string
  default = ""
}

variable "disk_size" {
  type        = string
  description = "Virtual (sparse) disk size of the box."
  default     = "64G"
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "vagrant_private_key" {
  type    = string
  default = "~/.vagrant.d/insecure_private_keys/vagrant.key.ed25519"
}

# Input for the virtualbox build: the OVF made by scripts/make-vbox-ovf.sh
# from the finished libvirt image.
variable "vbox_ovf" {
  type    = string
  default = "output-vbox-import/hako.ovf"
}

locals {
  box_name = "fedora-${var.os_version}"
  vm_name  = "hako-fedora-${var.os_version}-${var.arch}"
  box_dir  = "${path.root}/../boxes"

  efi_code_path = var.efi_code != "" ? var.efi_code : "${var.qemu_share_dir}/${local.cfg.efi_code}"
  efi_vars_path = var.efi_vars != "" ? var.efi_vars : "${var.qemu_share_dir}/${local.cfg.efi_vars}"

  # Per-architecture QEMU settings (as in ../ubuntu/packer). x86 uses the
  # same edk2 vars template as 32-bit x86 (edk2-i386-vars.fd pairs with
  # edk2-x86_64-code.fd).
  arch_cfg = {
    arm64 = {
      qemu_binary  = "qemu-system-aarch64"
      machine_type = "virt,highmem=on"
      efi_code     = "edk2-aarch64-code.fd"
      efi_vars     = "edk2-arm-vars.fd"
      cdrom_if     = "virtio-scsi"
    }
    amd64 = {
      qemu_binary  = "qemu-system-x86_64"
      machine_type = "q35"
      efi_code     = "edk2-x86_64-code.fd"
      efi_vars     = "edk2-i386-vars.fd"
      # On q35, "ide" is served by the built-in AHCI (see ../ubuntu/packer).
      cdrom_if = "ide"
    }
  }
  cfg = local.arch_cfg[var.arch]
}
