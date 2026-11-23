variable "box_version" {
  type        = string
  description = "Date-based box version, e.g. 2026.11.22."
}

variable "arch" {
  type        = string
  description = "Guest architecture. Arch Linux only publishes an x86_64 cloud image."
  default     = "amd64"

  validation {
    condition     = var.arch == "amd64"
    error_message = "Arch Linux boxes are amd64 only."
  }
}

variable "cloud_image_url" {
  type        = string
  description = "Override the cloud image URL (default: the latest arch-boxes cloud image)."
  default     = ""
}

variable "cloud_image_checksum" {
  type        = string
  description = "Override the cloud image checksum (default: the image's .SHA256 file)."
  default     = ""
}

variable "accelerator" {
  type        = string
  description = "QEMU accelerator: hvf on an Intel Mac, kvm on Linux."
  default     = "hvf"
}

variable "qemu_share_dir" {
  type        = string
  description = "QEMU data dir holding the edk2 firmware (Homebrew: $(brew --prefix)/share/qemu)."
  default     = "/opt/homebrew/share/qemu"
}

# Full paths to the UEFI firmware, for hosts whose QEMU does not ship the
# edk2-*.fd files (Debian/Ubuntu: /usr/share/OVMF/OVMF_CODE_4M.fd and
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
  box_name = "archlinux"
  vm_name  = "hako-archlinux-${var.arch}"
  box_dir  = "${path.root}/../boxes"

  # Official cloud image from the arch-boxes project (rebuilt regularly),
  # served by Arch's GeoDNS mirror. It ships cloud-init, like Ubuntu's.
  image_base = "https://geo.mirror.pkgbuild.com/images/latest"
  cloud_image_url = (var.cloud_image_url != "" ? var.cloud_image_url
    : "${local.image_base}/Arch-Linux-x86_64-cloudimg.qcow2")
  cloud_image_checksum = (var.cloud_image_checksum != "" ? var.cloud_image_checksum
    : "file:${local.image_base}/Arch-Linux-x86_64-cloudimg.qcow2.SHA256")

  efi_code_path = var.efi_code != "" ? var.efi_code : "${var.qemu_share_dir}/${local.cfg.efi_code}"
  efi_vars_path = var.efi_vars != "" ? var.efi_vars : "${var.qemu_share_dir}/${local.cfg.efi_vars}"

  # x86 uses the same edk2 vars template as 32-bit x86
  # (edk2-i386-vars.fd pairs with edk2-x86_64-code.fd).
  cfg = {
    qemu_binary  = "qemu-system-x86_64"
    machine_type = "q35"
    efi_code     = "edk2-x86_64-code.fd"
    efi_vars     = "edk2-i386-vars.fd"
    # On q35, "ide" is served by the built-in AHCI (see ../ubuntu/packer).
    cdrom_if     = "ide"
  }
}
