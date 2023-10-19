{ ... }:

{

  # Remove perl from activation
  boot.initrd.systemd.enable = true;
  system.rebuildable = false;

  # Perl remnants
  system.disableInstallerTools = true;
  programs.less.lessopen = null;
  programs.command-not-found.enable = false;
  boot.enableContainers = false;
  environment.defaultPackages = [ ];
  documentation.info.enable = false;

  system.forbiddenDependenciesRegex = "perl";

}
