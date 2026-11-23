# Vagrantfile embedded in every hako box (merged under the user's own
# Vagrantfile, which wins on any conflicting setting).
Vagrant.configure("2") do |config|
  config.vm.box_check_update = true

  # A virtio RNG from the host. Without one, Rocky's kernel takes about six
  # seconds to gather boot entropy under HVF (systemd-random-seed and
  # lvm2-monitor wait for it), doubling the boot time. A Vagrantfile that
  # sets its own extra_qemu_args replaces this one.
  config.vm.provider "qemu" do |qe|
    qe.extra_qemu_args = %w(-device virtio-rng-pci)
  end
  config.vm.provider "libvirt" do |lv|
    lv.random model: "random"
  end
end
