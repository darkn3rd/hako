build {
  name = "hako"
  sources = [
    "source.qemu.libvirt",
    "source.virtualbox-ovf.virtualbox",
  ]

  # --- libvirt: configure the fresh VM image ----------------------------
  # nuageinit installs sudo after SSH can already be up: wait for it.
  provisioner "shell" {
    only = ["qemu.libvirt"]
    inline = [
      "i=0; until command -v sudo >/dev/null; do i=$((i+1)); [ $i -lt 300 ] || exit 1; sleep 1; done",
      "mkdir -p /tmp/hako",
    ]
  }

  provisioner "file" {
    only = ["qemu.libvirt"]
    sources = [
      "${path.root}/../files/loader.conf.hako",
    ]
    destination = "/tmp/hako/"
  }

  provisioner "shell" {
    only             = ["qemu.libvirt"]
    execute_command  = "chmod +x '{{ .Path }}'; {{ .Vars }} sudo -E sh -eu '{{ .Path }}'"
    environment_vars = ["HAKO_IMAGE=${var.image_source}", "HAKO_VERSION=${var.box_version}", "HAKO_BOX=hako/${local.box_name}"]
    scripts          = ["${path.root}/../scripts/base.sh"]
  }

  # Boot the updated system once before packaging (freebsd-update installs
  # a new kernel for the next boot). sshd stops right away (this session
  # survives it), so Packer can only reconnect to the new boot.
  provisioner "shell" {
    only              = ["qemu.libvirt"]
    inline            = ["sudo shutdown -r +5s", "sudo service sshd stop"]
    expect_disconnect = true
    pause_after       = "45s"
  }

  provisioner "shell" {
    only   = ["qemu.libvirt"]
    inline = ["freebsd-version -kru", "uname -a"]
  }

  # --- virtualbox: the image is already configured; add guest support ----
  provisioner "shell" {
    only            = ["virtualbox-ovf.virtualbox"]
    execute_command = "chmod +x '{{ .Path }}'; {{ .Vars }} sudo -E sh -eu '{{ .Path }}'"
    scripts         = ["${path.root}/../scripts/guest-additions.sh"]
  }

  # --- every provider -----------------------------------------------------
  provisioner "shell" {
    execute_command = "chmod +x '{{ .Path }}'; {{ .Vars }} sudo -E sh -eu '{{ .Path }}'"
    scripts         = ["${path.root}/../scripts/cleanup.sh"]
  }

  post-processor "vagrant" {
    output               = "${local.box_dir}/${local.box_name}-${var.box_version}-{{ .Provider }}-${var.arch}.box"
    vagrantfile_template = "${path.root}/../vagrantfiles/box.rb"
    compression_level    = 6
    keep_input_artifact  = true
  }
}
