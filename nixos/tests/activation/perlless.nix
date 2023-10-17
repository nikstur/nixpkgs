{ lib, ... }:

{

  name = "activation-perlless";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine = { modulesPath, ... }: {
    imports = [ "${modulesPath}/profiles/perlless.nix" ];

    virtualisation.mountHostNixStore = false;
    virtualisation.useNixStoreImage = true;
  };

  testScript = ''
    perl_store_paths = machine.succeed("ls /nix/store | grep perl || true")
    print(perl_store_paths)
    assert len(perl_store_paths) == 0
  '';

}
