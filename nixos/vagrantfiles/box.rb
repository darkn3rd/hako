# Vagrantfile embedded in every hako box (merged under the user's own
# Vagrantfile, which wins on any conflicting setting).
Vagrant.configure("2") do |config|
  config.vm.box_check_update = true

  # NixOS generates /etc/fstab (read-only); Vagrant must not append its
  # shared-folder mounts there. They are mounted on each `vagrant up`.
  config.vm.allow_fstab_modification = false

  # A virtio RNG from the host, so the guest never waits for boot entropy.
  # A Vagrantfile that sets its own extra_qemu_args replaces this one.
  config.vm.provider "qemu" do |qe|
    qe.extra_qemu_args = %w(-device virtio-rng-pci)
  end
  config.vm.provider "libvirt" do |lv|
    lv.random model: "random"
  end

  # Linux has VirtualBox guest modules (vboxsf) only on x86, so on an arm64
  # host (boxes are never emulated, so the guest is arm64 too) the default
  # shared folder is copied in with rsync instead.
  if RbConfig::CONFIG["host_cpu"] =~ /arm64|aarch64/
    config.vm.provider "virtualbox" do |_vb, override|
      override.vm.synced_folder ".", "/vagrant", type: "rsync"
    end
  end
end
