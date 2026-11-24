# Step 1 (make build-installer): install EndeavourOS onto the helper's second disk.
build {
  name    = "install"
  sources = ["source.qemu.installer"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/hako"]
  }

  provisioner "file" {
    sources = [
      "${path.root}/../files/99-hako-ethernet.network",
      "${path.root}/../files/hako-ssh-hostkeys.service",
      "${path.root}/../files/hako-pacman-init.service",
    ]
    destination = "/tmp/hako/"
  }

  provisioner "shell" {
    execute_command  = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    environment_vars = ["HAKO_VERSION=${var.box_version}", "HAKO_BOX=hako/${local.box_name}"]
    scripts          = ["${path.root}/../scripts/install.sh"]
  }
}

# Step 2: the boxes.
build {
  name = "hako"
  sources = [
    "source.qemu.libvirt",
    "source.virtualbox-ovf.virtualbox",
  ]

  # libvirt: the installed system, booted for the first time.
  provisioner "shell" {
    only            = ["qemu.libvirt"]
    execute_command = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    scripts         = ["${path.root}/../scripts/firstboot.sh"]
  }

  # virtualbox: VirtualBox guest support where Linux has it (x86_64).
  provisioner "shell" {
    only            = ["virtualbox-ovf.virtualbox"]
    execute_command = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    scripts         = ["${path.root}/../scripts/guest-additions.sh"]
  }

  # --- every provider -----------------------------------------------------
  provisioner "shell" {
    execute_command  = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    environment_vars = ["HAKO_PROVIDER=${source.name}"]
    scripts          = ["${path.root}/../scripts/cleanup.sh"]
  }

  post-processor "vagrant" {
    output               = "${local.box_dir}/${local.box_name}-${var.box_version}-{{ .Provider }}-${var.arch}.box"
    vagrantfile_template = "${path.root}/../vagrantfiles/box.rb"
    compression_level    = 6
    keep_input_artifact  = true
  }
}
