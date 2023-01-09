let
  sources = import ./nix/sources.nix { };
  pkgs = import sources.nixpkgs { };
in
pkgs.mkShell {
  packages = [
    pkgs.python3
    pkgs.nixpkgs-fmt # A formatter for Nix code
  ];
}
