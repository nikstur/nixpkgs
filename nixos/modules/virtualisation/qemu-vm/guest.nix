{ config, lib, ... }:

let

  cfg = config.virtualisation;

in

{

  options.vitualisation = {

    emptyDiskImages = lib.mkOption {
      default = { };
      example = {
        name = {
          size = "1G";
          filesystem = "ext4";
        };
      };
      description = lib.mdDoc ''
        Disk images to provide to the VM.
      '';
      type = with lib.types; attrsOf (submodule {
        options = {

          size = mkOption {
            type = str;
          };

          format = mkOption {
            type = enum [ "raw" "qcow2" ];
            default = "qcow2";
          };

          filesystem = mkOption {
            type = enum [ "none" "ext4" ];
            default = "none";
          };

        };
      });
    };

    backedDiskImages = lib.mkOption {
      example = {
        name = {
          file = "/path/to/image.raw";
          sourceFormat = "raw";
          targetFormat = "qcow2";
        };
      };
      description = lib.mdDoc ''
        Disk images backed by another image.

        This is implemented as a Copy-on-Write image on top of the source file.
      '';
      type = with lib.types; attrsOf (submodule {
        options = {

          file = mkOption {
            type = path;
          };

          sourceFormat = mkOption {
            type = enum [ "raw" "qcow2" ];
            default = "raw";
          };

          targetFormat = mkOption {
            type = enum [ "raw" "qcow2" ];
            default = "qcow2";
          };

        };
      });
    };

    sharedDirectories = lib.mkOption {
      default = { };
      example = {
        my-share = { source = "/path/to/be/shared"; target = "/mnt/shared"; };
      };
      description = lib.mdDoc ''
        An attributes set of directories that will be shared with the
        virtual machine using VirtFS (9P filesystem over VirtIO).
        The attribute name will be used as the 9P mount tag.
      '';
      type = with lib.types; attrsOf (submodule {
        options = {

          source = mkOption {
            type = str;
            description = lib.mdDoc "The path of the directory to share, can be a shell variable";
          };

          target = mkOption {
            type = path;
            description = lib.mdDoc "The mount point of the directory inside the virtual machine";
          };

          fsOptions = mkOption {
            type = attrsOf str;
            default = {
              trans = "virtio";
              version = "9p2000.L";
              msize = "16384";
            };
            description = lib.mdDoc "`fileSystems` options for the shared directory";
          };

        };
      });
    };


    networking = {

      interfaces = lib.mkOption {
        default = { };
        example = {
          enp1s0.vlan = 1;
        };
        description = lib.mdDoc ''
          Network interfaces to add to the VM.
        '';
        type = with lib.types; attrsOf (submodule {
          options = {

            vlan = mkOption {
              type = ints.unsigned;
              description = lib.mdDoc ''
                VLAN to which the network interface is connected.
              '';
            };

            assignIP = mkOption {
              type = bool;
              default = false;
              description = lib.mdDoc ''
                Automatically assign an IP address to the network interface
                using the same scheme as virtualisation.vlans.
              '';
            };
          };
        });
      };

      vlans = lib.mkOption {
        type = lib.types.listOf lib.types.ints.unsigned;
        default = if cfg.interfaces == { } then [ 1 ] else [ ];
        defaultText = lib.literalExpression ''if cfg.interfaces == {} then [ 1 ] else [ ]'';
        example = [ 1 2 ];
        description = lib.mdDoc ''
          Virtual networks to which the VM is connected.  Each number «N» in
          this list causes the VM to have a virtual Ethernet interface attached
          to a separate virtual network on which it will be assigned IP address
          `192.168.«N».«M»`, where «M» is the index of this VM in the list of
          VMs.
        '';
      };

    };

  };

  config = {


    fileSystems =
      let
        mkSharedDir = tag: share: {
          name = share.target;
          value = {
            device = tag;
            fsType = "9p";
            neededForBoot = true;
            options = lib.mapAttrsToList (lib.generators.mkKeyValueDefault { } "=") share.fsOptions;
          };
        };
      in
      lib.mapAttrs' mkSharedDir cfg.sharedDirectories;


    boot.initrd = {

      availableKernelModules = lib.optional cfg.writableStore "overlay";

      postMountCommands = lib.mkIf (!config.boot.initrd.systemd.enable) ''
        # Mark this as a NixOS machine.
        mkdir -p $targetRoot/etc
        echo -n > $targetRoot/etc/NIXOS

        # Fix the permissions on /tmp.
        chmod 1777 $targetRoot/tmp

        mkdir -p $targetRoot/boot

        ${lib.optionalString cfg.writableStore ''
          echo "mounting overlay filesystem on /nix/store..."
          mkdir -p -m 0755 $targetRoot/nix/.rw-store/store $targetRoot/nix/.rw-store/work $targetRoot/nix/store
          mount -t overlay overlay $targetRoot/nix/store \
            -o lowerdir=$targetRoot/nix/.ro-store,upperdir=$targetRoot/nix/.rw-store/store,workdir=$targetRoot/nix/.rw-store/work || fail
        ''}
      '';

      systemd = lib.mkIf (config.boot.initrd.systemd.enable && cfg.writableStore) {
        mounts = [{
          where = "/sysroot/nix/store";
          what = "overlay";
          type = "overlay";
          options = "lowerdir=/sysroot/nix/.ro-store,upperdir=/sysroot/nix/.rw-store/store,workdir=/sysroot/nix/.rw-store/work";
          wantedBy = [ "initrd-fs.target" ];
          before = [ "initrd-fs.target" ];
          requires = [ "rw-store.service" ];
          after = [ "rw-store.service" ];
          unitConfig.RequiresMountsFor = "/sysroot/nix/.ro-store";
        }];
        services.rw-store = {
          unitConfig = {
            DefaultDependencies = false;
            RequiresMountsFor = "/sysroot/nix/.rw-store";
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/bin/mkdir -p -m 0755 /sysroot/nix/.rw-store/store /sysroot/nix/.rw-store/work /sysroot/nix/store";
          };
        };
      };

    };


    systemd.tmpfiles.rules = lib.mkIf config.boot.initrd.systemd.enable [
      "f /etc/NIXOS 0644 root root -"
      "d /boot 0644 root root -"
    ];

    # Don't run ntpd in the guest. It should get the correct time from KVM.
    services.timesyncd.enable = false;

    networking = {
      # Speed up booting by not waiting for ARP.
      dhcpcd.extraConfig = "noarp";

      usePredictableInterfaceNames = false;
    };

    system.requiredKernelConfig = with config.lib.kernelConfig; [
      (isEnabled "VIRTIO_BLK")
      (isEnabled "VIRTIO_PCI")
      (isEnabled "VIRTIO_NET")
      (isEnabled "EXT4_FS")
      (isEnabled "NET_9P_VIRTIO")
      (isEnabled "9P_FS")
      (isYes "BLK_DEV")
      (isYes "PCI")
      (isYes "NETDEVICES")
      (isYes "NET_CORE")
      (isYes "INET")
      (isYes "NETWORK_FILESYSTEMS")
      (isYes "SERIAL_8250_CONSOLE")
      (isYes "SERIAL_8250")
    ] ++ optionals (cfg.writableStore) [
      (isEnabled "OVERLAY_FS")
    ];
  };

  meta.maintainers = with lib.maintainers; [ nikstur raitobezarius ];

}
