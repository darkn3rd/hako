# Vagrantfile embedded in every hako box (merged under the user's own
# Vagrantfile, which wins on any conflicting setting).
Vagrant.configure("2") do |config|
  config.vm.box_check_update = true

  # FreeBSD has no bash in the base system.
  config.ssh.shell = "sh"

  # Vagrant cannot mount VirtualBox shared folders in a FreeBSD guest, so
  # the default shared folder is copied in with rsync (in the box).
  config.vm.synced_folder ".", "/vagrant", type: "rsync"

  # A virtio RNG from the host, so the guest never waits for boot entropy.
  # A Vagrantfile that sets its own extra_qemu_args replaces this one.
  config.vm.provider "qemu" do |qe|
    qe.extra_qemu_args = %w(-device virtio-rng-pci)
  end
  config.vm.provider "libvirt" do |lv|
    lv.random model: "random"
  end
end
