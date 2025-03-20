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

  testScript = # python
    ''
      machine.start()
      machine.wait_for_unit("default.target")
    '';
}
