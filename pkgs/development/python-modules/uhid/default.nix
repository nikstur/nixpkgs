{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
}:

buildPythonPackage (finalAttrs: {
  pname = "uhid";
  version = "0.0.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "FFY00";
    repo = "python-uhid";
    tag = finalAttrs.version;
    hash = "sha256-2F0HGCt2Z9Rqfn6AIqzdsULpp4grfyj5vMbOUrlzLQM=";
  };

  build-system = [ setuptools ];

  pythonImportsCheck = [ "uhid" ];

  meta = {
    description = "Pure Python typed Linux UHID wrapper ";
    homepage = "https://github.com/FFY00/python-uhid";
    license = lib.licenses.mit;
  };
})
