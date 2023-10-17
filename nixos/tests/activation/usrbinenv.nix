{ lib, ... }:

{

  name = "activation-usrbinenv";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine = { };

  testScript = ''
    assert machine.succeed("stat -c '%a' /usr/bin") == "755\n"
    assert machine.succeed("stat -c '%F' /usr/bin/env") == "symbolic link\n"
  '';
}
