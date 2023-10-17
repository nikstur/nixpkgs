{ lib, ... }:

let
  rootPassword = "$y$j9T$p6OI0WN7.rSfZBOijjRdR.$xUOA2MTcB48ac.9Oc5fz8cxwLv1mMqabnn333iOzSA6";
  normaloPassword = "hello";
in

{

  name = "activation-mutable-users-groups";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine = {
    boot.initrd.systemd.enable = true;

    users.mutableUsers = true;
    users.users.root.initialHashedPassword = rootPassword;
    users.users.normalo = {
      isNormalUser = true;
      initialPassword = normaloPassword;
    };
  };

  testScript = ''
    sysusers_service = machine.succeed("systemctl cat systemd-sysusers.service")
    print(sysusers_service)
    assert "SetCredential=passwd.hashed-password.root:${rootPassword}" in sysusers_service
    assert "SetCredential=passwd.plaintext-password.normalo:${normaloPassword}" in sysusers_service

    # Check that home diretoy is created and owned by the user
    print(machine.succeed("stat -c '%U' /home/normalo"))
  '';
}
