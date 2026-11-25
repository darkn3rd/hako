# Vagrantfile embedded in every hako box (merged under the user's own
# Vagrantfile, which wins on any conflicting setting).
Vagrant.configure("2") do |config|
  config.vm.box_check_update = true

  # vagrant-qemu on an Intel Mac (x86_64 host) defaults to `-cpu host`. Under
  # HVF that exposes AVX-512 without its XSAVE state, and the kernel panics at
  # boot (invalid opcode). A named model without AVX-512 avoids it; this is
  # the same model as packer/variables.pkr.hcl. KVM on Linux handles AVX-512
  # correctly, so only macOS is changed.
  if RbConfig::CONFIG["host_os"] =~ /darwin/ && RbConfig::CONFIG["host_cpu"] =~ /x86_64/
    config.vm.provider "qemu" do |qe|
      qe.cpu = "Skylake-Client"
    end
  end
end
