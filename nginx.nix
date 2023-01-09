{ config, ... }:

{
  services.nginx = {
    enable = true;
    virtualHosts."_" = {
      root = "/var/nginx";
    };
  };
}
