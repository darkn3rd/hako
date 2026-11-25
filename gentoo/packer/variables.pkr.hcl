variable "box_version" {
  type        = string
  description = "Date-based box version, e.g. 2026.11.22."
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

# Gentoo names each weekly image after its build timestamp, so there is no
# stable URL: the Makefile looks both up (scripts/cloud-image.sh).
variable "cloud_image_url" {
  type        = string
  description = "Gentoo cloud-init disk image (di-<arch>-cloudinit-<timestamp>.qcow2)."
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

locals {
  box_name = "gentoo"
  vm_name  = "hako-gentoo-${var.arch}"
  box_dir  = "${path.root}/../boxes"

  # HVF on an Intel Mac passes the host's AVX-512 CPUID bits through but does
  # not enable the AVX-512 XSAVE state, so Gentoo's 6.18 kernel executes an
  # AVX-512 (chacha) instruction at boot and panics with "invalid opcode".
  # A named model without AVX-512 avoids it. Keep the same model in
  # vagrantfiles/box.rb, which vagrant-qemu would otherwise default to "host".
  cpu_model = var.arch == "amd64" && var.accelerator == "hvf" ? "Skylake-Client" : "host"

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
