build {
  name    = "hako"
  sources = ["source.qemu.libvirt"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/hako"]
  }

  provisioner "file" {
    sources = [
      "${path.root}/../files/99-hako-ethernet.network",
      "${path.root}/../files/99-hako.cfg",
      "${path.root}/../files/ds-identify.cfg",
      "${path.root}/../files/hako-ssh-hostkeys.service",
    ]
    destination = "/tmp/hako/"
  }

  provisioner "shell" {
    execute_command  = "{{ .Vars }} sudo -E bash -euo pipefail '{{ .Path }}'"
    environment_vars = ["HAKO_IMAGE=${var.cloud_image_url}", "HAKO_VERSION=${var.box_version}"]
    scripts = [
      "${path.root}/../scripts/base.sh",
      "${path.root}/../scripts/cleanup.sh",
    ]
  }

  post-processor "vagrant" {
    output               = "${local.box_dir}/${local.box_name}-${var.box_version}-{{ .Provider }}-${var.arch}.box"
    vagrantfile_template = "${path.root}/../vagrantfiles/box.rb"
    compression_level    = 6
    keep_input_artifact  = true
  }
}
