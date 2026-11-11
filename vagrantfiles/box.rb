# Vagrantfile embedded in every hako box (merged under the user's own
# Vagrantfile, which wins on any conflicting setting).
Vagrant.configure("2") do |config|
  config.vm.box_check_update = true
end
