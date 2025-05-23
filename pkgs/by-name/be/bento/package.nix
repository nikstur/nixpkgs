{
  lib,
  fetchFromGitHub,
  buildGoModule,
  versionCheckHook,
  nix-update-script,
}:

buildGoModule rec {
  pname = "bento";
  version = "1.6.1";

  src = fetchFromGitHub {
    owner = "warpstreamlabs";
    repo = "bento";
    tag = "v${version}";
    hash = "sha256-T13r41ygQNmEBCwTKyCocQbGcyJSQ8lvmRllbxU512Y=";
  };

  proxyVendor = true;
  vendorHash = "sha256-/DXdPL98Y4peF3USV9/J4sT/TUTRp3Cds500kxb18QA=";

  subPackages = [
    "cmd/bento"
    "cmd/serverless/bento-lambda"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/warpstreamlabs/bento/internal/cli.Version=${version}"
    "-X main.Version=${version}"
  ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "High performance and resilient stream processor";
    homepage = "https://warpstreamlabs.github.io/bento/";
    changelog = "https://github.com/warpstreamlabs/bento/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ genga898 ];
    mainProgram = "bento";
  };
}
