{ lib, ... }:

{

  name = "activation-var";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine = { };

  testScript = ''
    assert machine.succeed("stat -c '%a' /var/tmp") == "1755\n"
    assert machine.succeed("stat -c '%a' /var/empty") == "555\n"
    assert machine.succeed("stat -c '%U' /var/empty") == "root\n"
    assert machine.succeed("stat -c '%G' /var/empty") == "root\n"
  '';
}
