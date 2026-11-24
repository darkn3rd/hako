# VirtualBox box (ARM or x86, matching var.arch). Input is the finished
# libvirt image, converted to a VMDK inside an OVF by scripts/make-vbox-ovf.sh
# (Packer cannot import a qcow2 into VirtualBox itself). The image already has
# the vagrant user, so this build only adds VirtualBox guest support from
# FreeBSD packages (see guest-additions.sh).
source "virtualbox-ovf" "virtualbox" {
  source_path      = "${path.root}/../${var.vbox_ovf}"
  vm_name          = local.vm_name
  output_directory = "${path.root}/../output-virtualbox"
  headless         = true

  # The Guest Additions ISO has no FreeBSD additions.
  guest_additions_mode = "disable"

  vboxmanage = [
    ["modifyvm", "{{ .Name }}", "--cpus", "${var.cpus}", "--memory", "${var.memory}"],
  ]

  communicator         = "ssh"
  ssh_username         = "vagrant"
  ssh_private_key_file = pathexpand(var.vagrant_private_key)
  ssh_timeout          = "10m"
  shutdown_command     = "sudo shutdown -p now"
}
