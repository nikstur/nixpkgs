{ lib, pkgs, ... }:

{
  options.system.nixos-init = {
    enable = lib.mkEnableOption ''
      nixos-init, a system for bashless initialization.

      This doesn't use any `activationScripts`. Anything set in these options is
      a no-op here.
    '';

    package = lib.mkPackageOption pkgs "nixos-init" { };
  };
}
