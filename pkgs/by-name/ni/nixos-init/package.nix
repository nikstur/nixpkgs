{
  lib,
  rustPlatform,
  clippy,
  rustfmt,
}:

let
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = cargoToml.package.name;
  inherit (cargoToml.package) version;

  src = lib.sourceFilesBySuffices ./. [
    ".rs"
    ".toml"
    ".lock"
  ];

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  stripAllList = [ "bin" ];

  passthru.tests = {
    clippy = finalAttrs.finalPackage.overrideAttrs (
      _: previousAttrs: {
        pname = previousAttrs.pname + "-clippy";
        nativeCheckInputs = (previousAttrs.nativeCheckInputs or [ ]) ++ [ clippy ];
        checkPhase = "cargo clippy";
      }
    );
    rustfmt = finalAttrs.finalPackage.overrideAttrs (
      _: previousAttrs: {
        pname = previousAttrs.pname + "-rustfmt";
        nativeCheckInputs = (previousAttrs.nativeCheckInputs or [ ]) ++ [ rustfmt ];
        checkPhase = "cargo fmt --check";
      }
    );
  };

  meta = with lib; {
    license = licenses.mit;
    maintainers = with lib.maintainers; [ nikstur ];
  };
})
