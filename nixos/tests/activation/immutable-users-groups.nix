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

    users.mutableUsers = false;
    users.users.root.initialHashedPassword = lib.mkForce rootPassword;
    users.users.normalo = {
      isNormalUser = true;
      initialPassword = normaloPassword;
    };
  };

  testScript = ''
    machine.fail("systemctl status systemd-sysusers.service")
    machine.fail("ls /etc/sysusers.d")
    print(machine.succeed("getent passwd normalo"))

    # Check that home directory is created and owned by the user
    assert machine.succeed("stat -c '%U' /home/normalo") == "normalo\n"

    assert machine.succeed("stat -c '%a' /etc/passwd") == "644\n"
    assert machine.succeed("stat -c '%a' /etc/group") == "644\n"
    assert machine.succeed("stat -c '%a' /etc/shadow") == "0\n"
    assert machine.succeed("stat -c '%a' /etc/gshadow") == "0\n"
  '';
}
