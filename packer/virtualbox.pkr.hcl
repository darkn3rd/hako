# VirtualBox (ARM) box. Input is the finished libvirt image, converted to a
# VMDK inside an OVF by scripts/make-vbox-ovf.sh (Packer cannot import a
# qcow2 into VirtualBox itself). The image already has the vagrant user and
# a clean cloud-init state, so this build only adds the Guest Additions.
source "virtualbox-ovf" "virtualbox" {
  source_path      = "${path.root}/../${var.vbox_ovf}"
  vm_name          = local.vm_name
  output_directory = "${path.root}/../output-virtualbox"
  headless         = true

  guest_additions_mode = "upload"
  guest_additions_path = "/tmp/VBoxGuestAdditions.iso"
  # Default is the ISO shipped with the installed VirtualBox.

  vboxmanage = [
    ["modifyvm", "{{ .Name }}", "--cpus", "${var.cpus}", "--memory", "${var.memory}"],
  ]

  communicator         = "ssh"
  ssh_username         = "vagrant"
  ssh_private_key_file = pathexpand(var.vagrant_private_key)
  ssh_timeout          = "10m"
  shutdown_command     = "sudo shutdown -P now"
}
