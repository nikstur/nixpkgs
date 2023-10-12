{ lib, ... }: {

  name = "activation-etc";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine = {
    boot.initrd.systemd.enable = true;
  };

  testScript = ''
    machine.succeed("ls /etc")
    machine.succeed("findmnt --kernel --type overlay /etc")
  '';
}
