{ lib, ... }:

{

  name = "activation-binsh";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine = { };

  testScript = ''
    assert machine.succeed("stat -c '%a' /bin") == "755\n"
    assert machine.succeed("stat -c '%F' /bin/sh") == "symbolic link\n"
  '';
}

