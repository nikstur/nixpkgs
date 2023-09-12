{ config, lib, ... }:

let

  cfg = config.virtualisation;

  writableStoreOverlay = cfg.nixStore.writeableOverlay != null;

in

{

  options.vitualisation = {

    sharedDirectories = lib.mkOption {
      default = { };
      example = {
        "my-share" = {
          source = "/path/to/be/shared";
          target = "/mnt/shared";
        };
      };
      description = lib.mdDoc ''
        An attributes set of directories that will be shared with the
        virtual machine using VirtFS (9P filesystem over VirtIO).
        The attribute name will be used as the 9P mount tag.
      '';
      type = with lib.types; attrsOf (submodule {
        options = {

          source = lib.mkOption {
            type = str;
            description = lib.mdDoc ''
              The path of the directory to share.

              Can be a shell variable.
            '';
          };

          target = lib.mkOption {
            type = path;
            description = lib.mdDoc "The mount point of the directory inside the virtual machine.";
          };

          fsOptions = lib.mkOption {
            type = attrsOf str;
            default = {
              trans = "virtio";
              version = "9p2000.L";
              msize = "16384";
            };
            description = lib.mdDoc "`fileSystems` options for the shared directory.";
          };

        };
      });
    };


    nixStore = {

      mountFromHost = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc ''
          Mount the host's Nix store into the VM.
        '';
      };

      writableOverlay = lib.mkOption {
        type = lib.types.nullOr lib.types.enum [ "persistent" "temporary" ];
        default = null;
        description = lib.mdDoc ''
          If this is set to anything but `null`, an overlay filesystem is
          layered on top of the Nix store. This means that no data is written
          to the underlying directory anymore.

          If set to `persistent`, created overlay filesystem persists data
          written to Nix store to the block device that backs `/`.

          If set to `temporary`, an ephemeral tmpfs is layered over the Nix store.

          This option is useful when you have a read-only Nix store that you
          want to make writable, e.g. in a tests where you mount the Nix store
          from the host.
        '';
      };

      image = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc ''
          Build and use a disk image for the Nix store, instead of accessing
          the host's one through 9p.

          For applications which do a lot of reads from the store, this can
          drastically improve performance, but at the cost of disk space and
          image build time.

          As an alternative, you can use a bootloader which will provide you
          with a full NixOS system image containing a Nix store and avoid
          mounting the host nix store through
          {option}`virtualisation.mountHostNixStore`.
        '';
      };

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

            vlan = lib.mkOption {
              type = ints.unsigned;
              description = lib.mdDoc ''
                VLAN to which the network interface is connected.
              '';
            };

            assignIP = lib.mkOption {
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


  imports = [
    ../profiles/qemu-guest.nix
  ];


  config = {

    virtualisation.qemu = {
      fsDevices = lib.mapAttrs (n: v: { path = v; }) cfg.sharedDirectories;
    };


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

      availableKernelModules = lib.optional writableStoreOverlay "overlay";

      postMountCommands = lib.mkIf (!config.boot.initrd.systemd.enable && writableStoreOverlay) ''
        echo "mounting overlay filesystem on /nix/store..."
        mkdir -p -m 0755 $targetRoot/nix/.rw-store/store $targetRoot/nix/.rw-store/work $targetRoot/nix/store
        mount -t overlay overlay $targetRoot/nix/store \
          -o lowerdir=$targetRoot/nix/.ro-store,upperdir=$targetRoot/nix/.rw-store/store,workdir=$targetRoot/nix/.rw-store/work || fail
      '';

      systemd = lib.mkIf (config.boot.initrd.systemd.enable && writableStoreOverlay) {
        mounts = [{
          where = "/sysroot/nix/store";
          what = "overlay";
          type = "overlay";
          options = ''
            lowerdir=/sysroot/nix/.ro-store,upperdir=/sysroot/nix/.rw-store/store,workdir=/sysroot/nix/.rw-store/work
          '';
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
            ExecStart = ''
              /bin/mkdir -p -m 0755 \
              /sysroot/nix/.rw-store/store \
              /sysroot/nix/.rw-store/work \
              /sysroot/nix/store
            '';
          };
        };
      };

    };

    systemd.tmpfiles.rules = [
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
    ] ++ optionals writableStoreOverlay [
      (isEnabled "OVERLAY_FS")
    ];
  };

  meta.maintainers = with lib.maintainers; [ nikstur raitobezarius ];

}

