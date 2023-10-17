{ config, lib, ... }:

let
  cfg = config.systemd.sysusers;
in
{
  options.systemd.sysusers = {

    enable = lib.mkEnableOption (lib.mdDoc "systemd-sysusers") // {
      description = lib.mdDoc ''
        Atomically create system users and groups.

        Please see
        <https://www.freedesktop.org/software/systemd/man/systemd-sysusers.html>
        for more details.
      '';
    };

  };

  config = lib.mkIf cfg.enable {

    systemd.additionalUpstreamSystemUnits = [
      "systemd-sysusers.service"
    ];

  };

  meta.maintainers = with lib.maintainers; [ nikstur ];
}
