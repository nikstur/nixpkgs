{ lib
, stdenv
, fetchFromGitHub
}:

stdenv.mkDerivation {
  pname = "move-mount-beneath";
  version = "unstable-2023-08-01";

  src = fetchFromGitHub {
    owner = "brauner";
    repo = "move-mount-beneath";
    rev = "1d82e621c11a62e938cfa81a8fd9619e1f9841b8";
    hash = "sha256-HbUFURMUzcy1R6wJHXVwunXi11oD9hNHBGYA2Vf+t88=";
  };

  installPhase = ''
    runHook preInstall
    install -D move-mount $out/bin/move-mount
    runHook postInstall
  '';

  meta = {
    description = "Toy binary to illustrate adding a mount beneath an existing mount";
    homepage = "https://github.com/brauner/move-mount-beneath";
    # Check back with the maintainer as the repo does not contain an explicit
    # license. Also, this code is hopefully soon available in util-linux.
    license = lib.licenses.free;
    maintainers = with lib.maintainers; [ nikstur ];
  };
}
