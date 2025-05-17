{ lib, pkgs, ... }:

{
  name = "nixos-init";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine =
    { modulesPath, ... }:
    {
      imports = [
        "${modulesPath}/profiles/perlless.nix"
      ];
      virtualisation.mountHostNixStore = false;
      virtualisation.useNixStoreImage = true;

      system.nixos-init.enable = true;
    };

  testScript =
    { nodes, ... }: # python
    ''
      with subtest("init"):
        assert "${nodes.machine.system.build.toplevel}" == machine.succeed("readlink /run/booted-system").strip()

      with subtest("activation"):
        assert "${nodes.machine.system.build.toplevel}" == machine.succeed("readlink /run/current-system").strip()
        assert "${nodes.machine.hardware.firmware}/lib/firmware" == machine.succeed("cat /sys/module/firmware_class/parameters/path").strip()
        assert "${pkgs.kmod}/bin/modprobe" == machine.succeed("cat /proc/sys/kernel/modprobe").strip()

      machine.wait_for_unit("multi-user.target")
      with subtest("systemd state passing"):
        systemd_analyze_output = machine.succeed("systemd-analyze")
        print(systemd_analyze_output)
        assert "(initrd)" in systemd_analyze_output, "systemd-analyze has no information about the initrd"

        ps_output = machine.succeed("ps ax -o command | grep systemd | head -n 1")
        print(ps_output)
        assert "--deserialize" in ps_output, "--deserialize flag wasn't passed to systemd"
    '';
}
