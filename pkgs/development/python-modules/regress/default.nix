{ buildPythonPackage
, fetchFromGitHub
, rustPlatform
}:

buildPythonPackage rec {
  pname = "regress";
  version = "0.4.1";

  format = "pyproject";

  src = fetchFromGitHub {
    owner = "crate-py";
    repo = "regress";
    rev = "v${version}";
    hash = "sha256-IzNOcXc0hhPTBm4KGLVNKj8OBbRbuH+okw/DfS0UJAg=";
  };

  cargoDeps = rustPlatform.fetchCargoTarball {
    inherit src;
    name = "${pname}-${version}";
    hash = "sha256-IdST5HSX9/g6DeL9uP9v5LfppxtaP9SU1Ah36lp3XkU=";
  };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    rustPlatform.maturinBuildHook
  ];
}
