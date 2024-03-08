{ lib
, fetchFromGitHub
, stdenv
, autoreconfHook
, autoconf-archive
, libtool
, pkg-config
, python3
, gnu-efi
, pciutils
, bats
, check
}:

stdenv.mkDerivation rec {
  pname = "efibootguard";
  version = "0.16";

  src = fetchFromGitHub {
    owner = "siemens";
    repo = "efibootguard";
    rev = "v${version}";
    hash = "sha256-YezKZXNYAjSWEiaT9qcLdhdJg5BwdJHiTPVS73GG5vQ=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    autoreconfHook
    autoconf-archive
    libtool
    pkg-config
    python3
  ];

  buildInputs = [
    gnu-efi
    pciutils
  ];

  nativeCheckInputs = [
    bats
  ];

  checkInputs = [
    check
  ];

  configureFlags = [
    "--with-gnuefi-include-dir=${gnu-efi}/include/efi"
    "--with-gnuefi-lib-dir=${gnu-efi}/lib"
  ];

  doCheck = true;
  enableParallelBuilding = true;
  strictDeps = true;

  meta = with lib; {
    description = "A bootloader based on UEFI";
    longDescription = ''
      Simple UEFI boot loader with support for safely switching between current and updated partition sets
    '';
    homepage = "https://github.com/siemens/efibootguard";
    license = licenses.gpl2;
    maintainers = with maintainers; [ nikstur ];
  };
}
