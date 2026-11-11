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
      "${path.root}/../files/01-hako-netcfg.yaml",
      "${path.root}/../files/99-hako.cfg",
      "${path.root}/../files/hako-ssh-hostkeys.service",
    ]
    destination = "/tmp/hako/"
  }

  provisioner "shell" {
    only            = ["qemu.libvirt"]
    execute_command = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    scripts         = ["${path.root}/../scripts/base.sh"]
  }

  # Boot the upgraded kernel so the old one can be purged. The reboot is
  # scheduled a few seconds out and Packer pauses past it, so it reconnects
  # to the new boot instead of hanging on a half-stopped sshd.
  provisioner "shell" {
    only              = ["qemu.libvirt"]
    inline            = ["sudo systemd-run --on-active=3 systemctl reboot"]
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
