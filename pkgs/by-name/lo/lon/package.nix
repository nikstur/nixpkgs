{
  lib,
  fetchFromGitHub,
  rustPlatform,
  stdenv,
  darwin,
  makeBinaryWrapper,
  nix,
  nix-prefetch-git,
  git,
}:

rustPlatform.buildRustPackage rec {
  pname = "lon";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "nikstur";
    repo = "lon";
    rev = version;
    hash = "sha256-mbhz9/kdOhXUQ87LHGYiIm3zUjkFMamd/Pzz6xrikMs=";
  };

  sourceRoot = "${src.name}/rust/lon";

  cargoHash = "sha256-8xEnCkEsBbcIBZl30te0dZeZ1sxLK1hw0Ychl4cuYbU=";

  buildInputs = lib.optional stdenv.isDarwin (
    with darwin.apple_sdk.frameworks;
    [
      Security
      SystemConfiguration
    ]
  );

  nativeBuildInputs = [ makeBinaryWrapper ];

  # Only the unit test suite is designed to run in the sandbox.
  cargoTestFlags = "--bins";

  postInstall = ''
    wrapProgram $out/bin/lon --prefix PATH : ${
      lib.makeBinPath [
        nix
        nix-prefetch-git
        git
      ]
    }
  '';

  stripAllList = [ "bin" ];

  meta = with lib; {
    homepage = "https://github.com/nikstur/lon";
    description = "Lock & update Nix dependencies";
    license = licenses.mit;
    maintainers = with lib.maintainers; [ nikstur ];
    mainProgram = "lon";
  };
}
