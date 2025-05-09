{
  lib,
  python3Packages,
  fetchFromGitHub,
  dpkg,
  nix-update-script,
  testers,
  rockcraft,
  cacert,
  writableTmpDirAsHomeHook,
}:

python3Packages.buildPythonApplication rec {
  pname = "rockcraft";
  version = "1.10.0";

  src = fetchFromGitHub {
    owner = "canonical";
    repo = "rockcraft";
    rev = version;
    hash = "sha256-LrUs6/YRQYU0o1kmNdBhafvDIyw91FnW8+9i0Jj5f+Y=";
  };

  pyproject = true;
  build-system = with python3Packages; [ setuptools-scm ];

  dependencies = with python3Packages; [
    craft-application
    craft-archives
    craft-platforms
    spdx-lookup
    tabulate
  ];

  nativeCheckInputs =
    with python3Packages;
    [
      craft-platforms
      pytest-check
      pytest-mock
      pytest-subprocess
      pytestCheckHook
      writableTmpDirAsHomeHook
    ]
    ++ [ dpkg ];

  disabledTests = [
    "test_project_all_platforms_invalid"
    "test_run_init_flask"
    "test_run_init_django"
  ];

  disabledTestPaths = [
    # Relies upon info in the .git directory which is stripped by fetchFromGitHub,
    # and the version is overridden anyway.
    "tests/integration/test_version.py"
    # Tests non-Nix native packaging
    "tests/integration/test_setuptools.py"
  ];

  passthru = {
    updateScript = nix-update-script { };
    tests.version = testers.testVersion {
      package = rockcraft;
      command = "env SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt HOME=$(mktemp -d) rockcraft --version";
      version = "rockcraft ${version}";
    };
  };

  meta = {
    mainProgram = "rockcraft";
    description = "Create OCI images using the language from Snapcraft and Charmcraft";
    homepage = "https://github.com/canonical/rockcraft";
    changelog = "https://github.com/canonical/rockcraft/releases/tag/${version}";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ jnsgruk ];
    platforms = lib.platforms.linux;
  };
}
