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
  type    = string
  default = "arm64"
}

variable "cloud_image_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-arm64.img"
}

variable "cloud_image_checksum" {
  type    = string
  default = "file:https://cloud-images.ubuntu.com/releases/26.04/release/SHA256SUMS"
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

variable "qemu_efi_code" {
  type    = string
  default = "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
}

variable "qemu_efi_vars" {
  type    = string
  default = "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
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
}
