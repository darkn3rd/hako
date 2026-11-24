# Vagrantfile embedded in every hako box (merged under the user's own
# Vagrantfile, which wins on any conflicting setting).
Vagrant.configure("2") do |config|
  config.vm.box_check_update = true

  # A virtio RNG from the host. Without one, the EL10 kernel gathers boot
  # entropy slowly under HVF, and systemd-random-seed and lvm2-monitor wait
  # for it: AlmaLinux booted in 13 s instead of 5 s. A Vagrantfile that sets
  # its own extra_qemu_args replaces this one.
  config.vm.provider "qemu" do |qe|
    qe.extra_qemu_args = %w(-device virtio-rng-pci)
  end
  config.vm.provider "libvirt" do |lv|
    lv.random model: "random"
  end
end
