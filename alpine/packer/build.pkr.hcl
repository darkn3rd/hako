build {
  name = "hako"
  sources = [
    "source.qemu.libvirt",
    "source.virtualbox-ovf.virtualbox",
  ]

  # --- libvirt: configure the fresh cloud image -------------------------
  # The image has doas but not sudo or bash, which the steps below use.
  # (Upgrade first: new packages can need newer versions of installed ones.)
  provisioner "shell" {
    only = ["qemu.libvirt"]
    inline = [
      "cloud-init status --wait || true",
      "doas apk update",
      "doas apk upgrade --available",
      "doas apk add sudo bash",
      "echo 'vagrant ALL=(ALL) NOPASSWD: ALL' | doas tee /etc/sudoers.d/vagrant >/dev/null",
      "doas chmod 0440 /etc/sudoers.d/vagrant",
      "mkdir -p /tmp/hako",
    ]
  }

  provisioner "file" {
    only = ["qemu.libvirt"]
    sources = [
      "${path.root}/../files/99-hako.cfg",
      "${path.root}/../files/ds-identify.cfg",
      "${path.root}/../files/interfaces",
    ]
    destination = "/tmp/hako/"
  }

  provisioner "shell" {
    only             = ["qemu.libvirt"]
    execute_command  = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    environment_vars = ["HAKO_IMAGE=${var.cloud_image_url}", "HAKO_VERSION=${var.box_version}", "HAKO_BOX=hako/${local.box_name}"]
    scripts          = ["${path.root}/../scripts/base.sh"]
  }

  # --- virtualbox: the image is already configured; add guest support ----
  provisioner "shell" {
    only            = ["virtualbox-ovf.virtualbox"]
    inline          = ["mkdir -p /tmp/hako"]
  }

  provisioner "file" {
    only        = ["virtualbox-ovf.virtualbox"]
    sources     = ["${path.root}/../files/interfaces"]
    destination = "/tmp/hako/"
  }

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
