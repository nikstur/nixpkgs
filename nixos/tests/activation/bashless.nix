{ pkgs, ... }:

let
  bashlessProfile = {
  };
in
{
  name = "bashless";

  nodes.machine =
    { modulesPath, ... }:
    {
      imports = [
        "${modulesPath}/profiles/perlless.nix"
        bashlessProfile
      ];
      virtualisation.mountHostNixStore = false;
      virtualisation.useNixStoreImage = true;
    };

  testScript =
    { nodes, ... }: # python
    ''
      print(machine.succeed("ls -l /run/booted-system"))

      with subtest("init"):
        assert "${nodes.machine.system.build.toplevel}" == machine.succeed("readlink /run/booted-system").strip()

      with subtest("activation"):
        assert "${nodes.machine.system.build.toplevel}" == machine.succeed("readlink /run/current-system").strip()
        assert "${nodes.machine.hardware.firmware}/lib/firmware" == machine.succeed("cat /sys/module/firmware_class/parameters/path").strip()
        assert "${pkgs.kmod}/bin/modprobe" == machine.succeed("cat /proc/sys/kernel/modprobe").strip()
    '';
}
