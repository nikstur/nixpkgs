{ stdenvNoCC, initrd }:

stdenvNoCC.mkDerivation {
  name = "closure-info";

  preferLocalBuild = true;

  buildCommand = ''
    zstd -dfc ${initrd}/init | cpio -t | rg bash
  '';
}
