{ lib, ... }:

let
  rootPassword = "difnd";
  normaloPassword = "hello";
in

{

  name = "activation-users-groups";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine = {
    system.rebuildable = false;
    boot.initrd.systemd.enable = true;

    users.users.root.initialPassword = rootPassword;
    users.users.normalo = {
      isNormalUser = true;
      initialPassword = normaloPassword;
    };

    # Cursed nonsense

    # Requires "users" activationScript
    # system.activationScripts.borgbackup = lib.mkForce "";
    # system.activationScripts.upsSetup = lib.mkForce "";
    # system.activationScripts.vmwareWrappers = lib.mkForce "";
    # system.activationScripts.wrappers = lib.mkForce "";
    # system.activationScripts.ldap = lib.mkForce "";
    # system.activationScripts.create-test-cert = lib.mkForce "";

    # Requires "etc" activationScript
    system.activationScripts.nix-channel = lib.mkForce "";
  };

  testScript = ''
    sysusers_service = machine.succeed("systemctl cat systemd-sysusers.service")
    print(sysusers_service)
    # assert "SetCredential=passwd.plaintext-password.root:${rootPassword}" in sysusers_service
    assert "SetCredential=passwd.plaintext-password.normalo:${normaloPassword}" in sysusers_service

    print(machine.succeed("ls /home/normalo"))
    print(machine.succeed("stat /home/normalo"))
  '';
}
