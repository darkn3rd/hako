variable "box_version" {
  type        = string
  description = "Date-based box version, e.g. 2026.11.10."
}

variable "os_name" {
  type    = string
  default = "ubuntu"
}

variable "os_version" {
  type    = string
  default = "26.04"
}

variable "arch" {
  type        = string
  description = "Guest architecture: amd64 or arm64. Built natively, never emulated."
  default     = "arm64"

  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "The arch variable must be amd64 or arm64."
  }
}

variable "cloud_image_url" {
  type        = string
  description = "Override the cloud image URL (default: Ubuntu's release image for arch)."
  default     = ""
}

variable "cloud_image_checksum" {
  type        = string
  description = "Override the cloud image checksum (default: Ubuntu's SHA256SUMS)."
  default     = ""
}

variable "accelerator" {
  type    = string
  default = "hvf"
}

variable "qemu_share_dir" {
  type        = string
  description = "QEMU data dir holding the edk2 firmware (Homebrew: $(brew --prefix)/share/qemu)."
  default     = "/opt/homebrew/share/qemu"
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
  box_name = "${var.os_name}-${var.os_version}"
  vm_name  = "hako-${var.os_name}-${var.os_version}-${var.arch}"
  box_dir  = "${path.root}/../boxes"

  image_base = "https://cloud-images.ubuntu.com/releases/${var.os_version}/release"
  cloud_image_url = (var.cloud_image_url != "" ? var.cloud_image_url
    : "${local.image_base}/${var.os_name}-${var.os_version}-server-cloudimg-${var.arch}.img")
  cloud_image_checksum = (var.cloud_image_checksum != "" ? var.cloud_image_checksum
    : "file:${local.image_base}/SHA256SUMS")

  # Per-architecture QEMU settings. x86 uses the same edk2 vars template
  # as 32-bit x86 (edk2-i386-vars.fd pairs with edk2-x86_64-code.fd).
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
      # The plugin's "virtio-scsi" adds a virtio-scsi-device (MMIO), which
      # exists on arm's virt machine but not on q35, and "sata" is not a
      # valid -drive if=. On q35, "ide" is served by the built-in AHCI.
      cdrom_if     = "ide"
    }
  }
  cfg = local.arch_cfg[var.arch]
}
