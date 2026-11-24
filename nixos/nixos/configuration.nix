# NixOS configuration of the hako box (/etc/nixos/configuration.nix).
#
# Edit it in a VM and run `sudo nixos-rebuild switch`, as on any NixOS
# system. hardware-configuration.nix was generated when the box was
# installed; hako-provider.nix holds what differs between the libvirt and
# VirtualBox boxes; vagrant.nix, when present, is written by Vagrant (host
# name, private networks).
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hako-provider.nix
  ] ++ lib.optional (builtins.pathExists ./vagrant.nix) ./vagrant.nix;

  # systemd-boot at the removable-media path (EFI/BOOT/BOOT*.EFI), so the
  # box boots without NVRAM boot entries (Vagrant providers start from
  # fresh firmware variables). No menu wait.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.timeout = 0;
  boot.loader.systemd-boot.editor = false;

  # The 6.12 LTS kernel: NixOS's newer kernels (6.18 and later) leave out
  # the legacy iptables tables (CONFIG_NETFILTER_XTABLES_LEGACY), which
  # Docker's check-config.sh requires. It is in NixOS's binary cache.
  boot.kernelPackages = pkgs.linuxPackages_6_12;

  # Disk and NIC drivers for every hypervisor the box runs on: virtio
  # (QEMU, VirtualBox on Arm) and AHCI (VirtualBox on x86).
  boot.initrd.availableKernelModules = [
    "virtio_pci" "virtio_blk" "virtio_scsi" "virtio_net" "ahci" "sd_mod" "sr_mod"
  ];

  # DHCP on every ethernet NIC, whatever its name, with systemd-networkd.
  networking.hostName = "nixos";
  networking.useNetworkd = true;
  networking.useDHCP = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      UseDns = false;
    };
  };

  # Vagrant's conventions: user vagrant (password "vagrant", console only),
  # its insecure keys, and passwordless sudo.
  # Its own group, as on other boxes (Vagrant's rsync shared folders chown
  # to vagrant:vagrant).
  users.groups.vagrant = { };
  users.users.vagrant = {
    isNormalUser = true;
    group = "vagrant";
    description = "Vagrant";
    extraGroups = [ "wheel" ];
    password = "vagrant";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1YdxBpNlzxDqfJyw/QKow1F+wvG9hXGoqiysfJOn5Y vagrant insecure public key"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "root" "@wheel" ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # rsync: Vagrant's rsync shared folders; curl, git: fetching things.
  environment.systemPackages = with pkgs; [ rsync curl git ];

  # NixOS's /etc/bash_logout resets the terminal title (printf '\e]0;\a')
  # when a login shell exits. Vagrant runs its commands in "bash -l" and
  # parses their output, and the stray escape breaks that ("odd number of
  # arguments for Hash" from its sshd -T key type check on vagrant up).
  environment.etc."bash_logout".text = lib.mkForce "";

  # A smaller box: no NixOS manual or info pages.
  documentation.nixos.enable = false;
  documentation.info.enable = false;

  system.stateVersion = "26.05";
}
