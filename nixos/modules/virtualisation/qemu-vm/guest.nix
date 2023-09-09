{ config, lib, ... }:

let

  cfg = config.virtualisation;

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
    ] ++ optionals (cfg.writableStore) [
      (isEnabled "OVERLAY_FS")
    ];
  };

  meta.maintainers = with lib.maintainers; [ nikstur raitobezarius ];

}

