{ config, lib, ... }:

let

  inherit (lib) stringAfter;

in

{

  imports = [ ./etc.nix ];

  config = lib.mkMerge [

    (lib.mkIf (!config.boot.initrd.systemd.enable) {
      system.activationScripts.etc =
        stringAfter [ "users" "groups" ] config.system.build.etcActivationCommands;
    })

    (lib.mkIf config.boot.initrd.systemd.enable {
      system.activationScripts.etc = "";

      boot.initrd.availableKernelModules = [ "overlay" ];

      boot.initrd.systemd = {
        mounts = [{
          where = "/sysroot/etc";
          what = "overlay";
          type = "overlay";
          options = "lowerdir=/sysroot${config.system.build.etc}/etc,upperdir=/sysroot/.rw-etc/upper,workdir=/sysroot/.rw-etc/work";
          wantedBy = [ "initrd-fs.target" ];
          before = [ "initrd-fs.target" ];
          requires = [ "rw-etc.service" ];
          after = [ "rw-etc.service" ];
          unitConfig.RequiresMountsFor = "/sysroot/nix/store";
        }];
        services.rw-etc = {
          unitConfig = {
            DefaultDependencies = false;
            RequiresMountsFor = "/sysroot";
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/bin/mkdir -p -m 0755 /sysroot/.rw-etc/upper /sysroot/.rw-etc/work /sysroot/etc";
          };
        };
      };
    })

  ];
}
