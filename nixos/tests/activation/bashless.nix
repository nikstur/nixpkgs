{ lib, ... }:

{

  name = "activation-bashless";

  meta.maintainers = with lib.maintainers; [ nikstur ];

  nodes.machine =
    { pkgs, modulesPath, ... }:
    {
      imports = [ "${modulesPath}/profiles/bashless.nix" ];

      # This ensures that we only have the store paths of our closure in the
      # in the guest. This is necessary so we can grep in the store.
      virtualisation.mountHostNixStore = false;
      virtualisation.useNixStoreImage = true;
    };

  testScript = ''
    bash_store_paths = machine.succeed("ls /nix/store | grep bash || true")
    print(bash_store_paths)
    assert len(bash_store_paths) == 0
  '';

}
