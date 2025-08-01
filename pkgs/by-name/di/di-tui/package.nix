{
  lib,
  nix-update-script,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "di-tui";
  version = "1.11.2";

  src = fetchFromGitHub {
    owner = "acaloiaro";
    repo = "di-tui";
    rev = "v${version}";
    hash = "sha256-YXTVJN8t58MS0Q4kKbasFNkmB/Jz4ctebBnbKqOP2is=";
  };

  vendorHash = "sha256-b7dG0nSjPQpjWUbOlIxWudPZWKqtq96sQaJxKvsQT9I=";

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Simple terminal UI player for di.fm";
    homepage = "https://github.com/acaloiaro/di-tui";
    license = lib.licenses.bsd2;
    maintainers = [ lib.maintainers.acaloiaro ];
    mainProgram = "di-tui";
  };
}
