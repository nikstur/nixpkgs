# This profile sets up a sytem for appliance usage. an appliance is
# installed as an image, has no nix available and is generally not
# meant for interactive use.
{ config, lib, modulesPath, ... }:
{

  imports = [
    "${modulesPath}/profiles/minimal.nix"
  ];

  # This could go into minimal.nix.
  environment.defaultPackages = [];
  programs.less.lessopen = null;
  boot.enableContainers = lib.mkDefault false;

  # The system is static.
  users.mutableUsers = false;

  # The system avoids interpreters as much as possible.
  boot.initrd.systemd.enable = true;
  networking.useNetworkd = lib.mkDefault true;
  
  # The system cannot be rebuilt.
  nix.enable = false;
  system.rebuildable = false;
}
