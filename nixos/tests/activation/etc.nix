{ lib, ... }:

{

  name = "activation-etc";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine = {
    system.rebuildable = false;
    boot.initrd.systemd.enable = true;

    # Cursed nonsense
    # Requires "etc" activationScript
    system.activationScripts.nix-channel = lib.mkForce "";
  };

  testScript = ''
    machine.succeed("ls /etc")
    machine.succeed("findmnt --kernel --type overlay /etc")
  '';
}
