build {
  name = "hako"
  sources = [
    "source.qemu.libvirt",
    "source.virtualbox-ovf.virtualbox",
  ]

  # --- libvirt: configure the fresh cloud image -------------------------
  provisioner "shell" {
    only   = ["qemu.libvirt"]
    inline = ["mkdir -p /tmp/hako"]
  }

  provisioner "file" {
    only = ["qemu.libvirt"]
    sources = [
      "${path.root}/../files/99-hako.cfg",
      "${path.root}/../files/ds-identify.cfg",
      "${path.root}/../files/99-hako-ethernet.network",
      "${path.root}/../files/hako-ssh-hostkeys.service",
    ]
    destination = "/tmp/hako/"
  }

  provisioner "shell" {
    only             = ["qemu.libvirt"]
    execute_command  = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    environment_vars = ["HAKO_IMAGE=${var.cloud_image_url}", "HAKO_VERSION=${var.box_version}", "HAKO_BOX=hako/${local.box_name}"]
    scripts          = ["${path.root}/../scripts/base.sh"]
  }

  # Boot the upgraded kernel so the old one can be removed. The reboot is
  # scheduled a few seconds out and Packer pauses past it. sshd stops right
  # away (this session survives it), so however long the shutdown takes,
  # Packer can only reconnect to the new boot, never to the old one.
  provisioner "shell" {
    only              = ["qemu.libvirt"]
    inline            = ["sudo systemd-run --on-active=3 systemctl reboot", "sudo systemctl stop ssh.service ssh.socket"]
    expect_disconnect = true
    pause_after       = "45s"
  }

  provisioner "shell" {
    only            = ["qemu.libvirt"]
    execute_command = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    scripts         = ["${path.root}/../scripts/kernel.sh"]
  }

  # --- virtualbox: the image is already configured; add Guest Additions --
  provisioner "shell" {
    only            = ["virtualbox-ovf.virtualbox"]
    execute_command = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    scripts         = ["${path.root}/../scripts/guest-additions.sh"]
  }

  # --- every provider -----------------------------------------------------
  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    scripts         = ["${path.root}/../scripts/cleanup.sh"]
  }

  post-processor "vagrant" {
    output               = "${local.box_dir}/${local.box_name}-${var.box_version}-{{ .Provider }}-${var.arch}.box"
    vagrantfile_template = "${path.root}/../vagrantfiles/box.rb"
    compression_level    = 6
    keep_input_artifact  = true
  }
}
