{
  lib,
  pythonOlder,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  jmespath,
  jsonschema,
  jxmlease,
  ncclient,
  netaddr,
  paramiko,
  ansible-pylibssh,
  pynetbox,
  scp,
  textfsm,
  ttp,
  xmltodict,
  passlib,

  # optionals
  withJunos ? false,
  withNetbox ? false,
}:

let
  pname = "ansible";
  version = "11.7.0";
in
buildPythonPackage {
  inherit pname version;
  pyproject = true;

  disabled = pythonOlder "3.9";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-+d83xx1Af2W8ucXAbJkY4pfZ6nS1za9ZJsTJqp5E218=";
  };

  # we make ansible-core depend on ansible, not the other way around,
  # since when you install ansible-core you will not have ansible
  # executables installed in the PATH variable
  pythonRemoveDeps = [ "ansible-core" ];

  build-system = [ setuptools ];

  dependencies = lib.unique (
    [
      # Support ansible collections by default, make all others optional
      # ansible.netcommon
      passlib
      jxmlease
      ncclient
      netaddr
      paramiko
      ansible-pylibssh
      xmltodict
      # ansible.posix
      # ansible.utils
      jsonschema
      textfsm
      ttp
      xmltodict
      # ansible.windows

      # Default ansible collections dependencies
      # community.general
      jmespath

      # lots of collections with dedicated requirements.txt and pyproject.toml files,
      # add the dependencies for the collections you need conditionally and install
      # ansible using overrides to enable the collections you need.
    ]
    ++ lib.optionals withJunos [
      # ansible_collections/junipernetworks/junos/requirements.txt
      jxmlease
      ncclient
      paramiko
      ansible-pylibssh
      scp
      xmltodict
    ]
    ++ lib.optionals withNetbox [
      # ansible_collections/netbox/netbox/pyproject.toml
      pynetbox
    ]
  );

  # don't try and fail to strip 48000+ non strippable files, it takes >5 minutes!
  dontStrip = true;

  # difficult to test
  doCheck = false;

  meta = with lib; {
    description = "Radically simple IT automation";
    mainProgram = "ansible-community";
    homepage = "https://www.ansible.com";
    changelog = "https://github.com/ansible-community/ansible-build-data/blob/${version}/${lib.versions.major version}/CHANGELOG-v${lib.versions.major version}.rst";
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [
      HarisDotParis
      robsliwi
    ];
  };
}
