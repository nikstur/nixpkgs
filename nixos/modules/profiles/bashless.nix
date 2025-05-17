{ lib, ... }:

{

  # Remove bash from activation
  environment.enableShell = lib.mkDefault false;
  system.nixos-init.enable = lib.mkDefault true;
  boot.initrd.systemd.enable = lib.mkDefault true;
  system.etc.overlay.enable = lib.mkDefault true;
  services.userborn.enable = lib.mkDefault true;

  # Check that the system does not contain a Nix store path that contains the
  # string "bash".
  # system.forbiddenDependenciesRegexes = [ "bash" ];

}
