let
  pkgs = import ../../../.. { };
in
pkgs.mkShell {
  packages = [
    pkgs.clippy
    pkgs.rustfmt
    pkgs.rust-analyzer
  ];

  inputsFrom = [ pkgs.nixos-init ];

  RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
}
