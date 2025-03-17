let
  pkgs = import ../../../.. { };
in
pkgs.mkShell {
  packages = [
    pkgs.clippy
    pkgs.rustfmt
  ];

  inputsFrom = [ pkgs.prepare-root ];

  RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
}
