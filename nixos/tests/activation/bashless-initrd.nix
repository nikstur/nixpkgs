{
  stdenvNoCC,
  zstd,
  cpio,
  ripgrep,

  initrd,
}:

stdenvNoCC.mkDerivation {
  name = "closure-info";

  preferLocalBuild = true;

  nativeBuildInputs = [
    zstd
    cpio
    ripgrep
  ];

  buildCommand = ''
    zstd -dfc ${initrd}/initrd | cpio -t | rg shell
  '';
}
