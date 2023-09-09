# Configure a VM on the host. Only contains options to do this. All options
# that mix the levels of abstraction, i.e. configure something on the host AND
# in the guest belong in guest.nix. This module offers abstractions that can be
# used to build higher-level functionality.

{ config, lib, pkgs, options, ... }:

let

  qemu-common = import ../../lib/qemu-common.nix { inherit lib pkgs; };

  cfg = config.virtualisation;

  qemu = cfg.qemu.package;

  hostPkgs = cfg.host.pkgs;

in

{

  options.virtualisation = {

    memorySize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1024;
      description = lib.mdDoc ''
        The memory size of the virtual machine in megabytes (MB).
      '';
    };

    cores = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = lib.mdDoc ''
        The number of CPU cores avilable to the guest.

        These are virtual CPU cores and thus the number can be higher than the
        physically available cores on the host system.
      '';
    };

    graphics = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Whether to run the VM with a graphical window, or without one.
      '';
    };

    host.pkgs = lib.mkOption {
      type = options.nixpkgs.pkgs.type;
      default = pkgs;
      defaultText = lib.literalExpression "pkgs";
      example = lib.literalExpression ''
        import pkgs.path { system = "x86_64-darwin"; }
      '';
      description = lib.mdDoc ''
        pkgs set to use for the host-specific packages of the vm runner.

        Changing this to e.g. a Darwin package set allows running NixOS VMs on Darwin.
      '';
    };


    images = lib.mkOption {
      default = [ ];
      example = {
        "existing-image" = {
          file = "/path/to/existing/image.raw";
        };
        "image-to-create" = {
          file = "/path/to/image/to/create.raw";
          create = true;
          size = "1G";
        };
        "temporary-image-to-create" = {
          create = true;
          size = "1G";
        };
        "backed-image" = {
          file = "/path/to/target/image.qcow2";
          backing.file = "/path/to/source/image.raw";
        };
      };
      description = lib.mdDoc ''
        Images to be passed to the VM.

        You can create the images by setting `create = true;`.

        You can create an image backed by another via the `backing` option.
      '';
      type = with lib.types; attrsOf
        (submodule {
          options = {

            file = mkOption {
              type = nullOr str;
              description = lib.mdDoc ''
                Path to disk image on the host.

                If it's `null`, a tmpfile is created.
              '';
            };

            create = lib.mkOption {
              type = bool;
              default = false;
              description = lib.mdDoc "Whether to create the image before starting the VM.";
            };

            size = lib.mkOption {
              type = int;
              default = "512M";
              description = "Size of the image";
            };

            fsType = lib.mkOption {
              type = enum [ "ext4" "vfat" "btrfs" ];
              default = "ext4";
              description = lib.mdDoc ''
                The file system to create inside the image.
              '';
            };

            backing = lib.mkOption {
              example = {
                file = "/path/to/image.raw";
                sourceFormat = "raw";
              };
              description = lib.mdDoc ''
                Disk images backed by another image.

                This is implemented as a Copy-on-Write image on top of the source file.
              '';
              type = submodule {
                options = {

                  file = mkOption {
                    type = nullOr path;
                    default = null;
                    description = lib.mdDoc ''
                      The source file for creating a backed image.

                      If this is `null`, no backing image is created.
                    '';
                  };

                  sourceFormat = mkOption {
                    type = enum [ "raw" "qcow2" ];
                    default = "raw";
                  };

                };
              };
            };

          };
        });
    };


    firmware = {

      efi = {

        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc ''
            Whether to boot the VM with an UEFI firmware.
          '';
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = (pkgs.OVMF.override { inherit (cfg.firmware.efi) secureBoot; }).fd;
          defaultText = lib.literalExpression ''
            (pkgs.OVMF.override { inherit (cfg.firmware.efi) secureBoot; }).fd
          '';
          description = lib.mdDoc ''
            The package containing the UEFI implementation.

            Defaults to OVMF configured with secure boot support.
          '';
        };

        firmware = lib.mkOption {
          type = lib.types.path;
          default = cfg.firmware.efi.package.firmware;
          defaultText = lib.literalExpression
            "config.virtualisation.firmware.efi.package.firmware";
          description = lib.mdDoc ''
            Firmware binary for EFI implementation.
          '';
        };

        variables = lib.mkOption {
          type = lib.types.path;
          default = cfg.firmware.efi.package.variables;
          defaultText = lib.literalExpression
            "config.virtualisation.firmware.efi.package.variables";
          description = lib.mdDoc ''
            Flash binary for EFI variables.
          '';
        };

        secureBoot = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc ''
            Enable Secure Boot support in the EFI firmware.
          '';
        };
      };

      bios = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = lib.mdDoc ''
          An alternate BIOS (such as `qboot`) with which to start the VM.
          Should contain a file named `bios.bin`.

          If `null`, QEMU's builtin SeaBIOS will be used.
        '';
      };

    };


    boot = {

      direct = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = lib.mdDoc ''
          If enabled, the virtual machine will boot directly into the
          kernel instead of through a bootloader. Other relevant parameters
          such as the initrd are also passed to QEMU.

          This will not boot / reboot correctly into a system that has
          switched to a different configuration on disk.

          Read more about this feature:
          <https://qemu-project.gitlab.io/qemu/system/linuxboot.html>.
        '';
      };

      initrd = lib.mkOption {
        type = lib.types.str;
        default =
          "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
        defaultText = lib.literalExpression ''
          ''${config.system.build.initialRamdisk}/''${config.system.boot.loader.initrdFile};
        '';
        description = lib.mdDoc ''
          In direct boot situations, you may want to influence the initrd to load
          to use your own customized payload.

          This is useful if you want to test the netboot image without
          testing the firmware or the loading part.
        '';
      };

    };


    networking = {

      forwardPorts = lib.mkOption {
        default = [ ];
        example = lib.literalExpression ''
          [
            # forward local port 2222 -> 22, to ssh into the VM
            { from = "host"; host.port = 2222; guest.port = 22; }

            # forward local port 80 -> 10.0.2.10:80 in the VLAN
            { from = "guest";
              guest.address = "10.0.2.10"; guest.port = 80;
              host.address = "127.0.0.1"; host.port = 80;
            }
          ]
        '';
        description = lib.mdDoc ''
          When using the SLiRP user networking (default), this option allows to
          forward ports to/from the host/guest.

          ::: {.warning}
          If the NixOS firewall on the virtual machine is enabled, you also
          have to open the guest ports to enable the traffic between host and
          guest.
          :::

          ::: {.note}
          Currently QEMU supports only IPv4 forwarding.
          :::
        '';
        type = lib.types.listOf (lib.types.submodule {
          options = {

            from = lib.mkOption {
              type = lib.types.enum [ "host" "guest" ];
              default = "host";
              description = lib.mdDoc ''
                Controls the direction in which the ports are mapped:

                - `"host"` means traffic from the host ports
                  is forwarded to the given guest port.
                - `"guest"` means traffic from the guest ports
                  is forwarded to the given host port.
              '';
            };

            proto = lib.mkOption {
              type = lib.types.enum [ "tcp" "udp" ];
              default = "tcp";
              description = lib.mdDoc "The protocol to forward.";
            };

            host.address = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = lib.mdDoc "The IPv4 address of the host.";
            };

            host.port = lib.mkOption {
              type = lib.types.port;
              description = lib.mdDoc "The host port to be mapped.";
            };

            guest.address = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = lib.mdDoc "The IPv4 address on the guest VLAN.";
            };

            guest.port = lib.mkOption {
              type = lib.types.port;
              description = lib.mdDoc "The guest port to be mapped.";
            };

          };
        });
      };

      restrict = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = lib.mdDoc ''
          If this option is enabled, the guest will be isolated, i.e. it will
          not be able to contact the host and no guest IP packets will be
          routed over the host to the outside. This option does not affect
          any explicitly set forwarding rules.
        '';
      };

    };


    qemu = {

      package = lib.mkOption {
        type = lib.types.package;
        default = hostPkgs.qemu_kvm;
        defaultText = lib.literalExpression "config.virtualisation.host.pkgs.qemu_kvm";
        example = lib.literalExpression "pkgs.qemu_test";
        description = lib.mdDoc "QEMU package to use.";
      };

      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "-vga std" ];
        description = lib.mdDoc "Options passed to QEMU.";
      };

      blockDevices = lib.mkOption {
        description = lib.mdDoc "Block devices passed to QEMU.";
        type = lib.types.attrsOf (lib.types.submodule {
          options = {

            file = lib.mkOption {
              type = lib.types.str;
              description = lib.mdDoc ''
                The path to the file image on the host to use for this block device.
              '';
            };

            extraBlockdevOptions = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = lib.mdDoc "Extra options passed to `-blockdev`.";
            };

            extraDeviceOptions = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = lib.mdDoc "Extra options passed to `-device`.";
            };

          };
        });
      };

      fsDevices = lib.mkOption {
        description = lib.mdDoc "Fsdevices (9P) passed to QEMU.";
        type = lib.types.attrsOf (lib.types.submodule {
          options = {

            path = lib.mkOption {
              type = lib.types.str;
              description = lib.mdDoc "The path on the host to share with the VM.";
            };

          };
        });
      };

    };

  };

  config = {

    assertions =
      lib.concatLists
        (lib.flip lib.imap cfg.forwardPorts (i: rule:
          [
            {
              assertion = rule.from == "guest" -> rule.proto == "tcp";
              message = ''
                Invalid virtualisation.forwardPorts.<entry ${toString i}>.proto:

                Guest forwarding supports only TCP connections.
              '';
            }
            {
              assertion = rule.from == "guest" -> lib.hasPrefix "10.0.2." rule.guest.address;
              message = ''
                Invalid virtualisation.forwardPorts.<entry ${toString i}>.guest.address:

                The address must be in the default VLAN (10.0.2.0/24).
              '';
            }
          ])) ++ [
        {
          assertion = pkgs.stdenv.hostPlatform.is32bit -> cfg.memorySize < 2047;
          message = ''
            `virtualisation.memorySize` is set to a value larger than 2047, but
            QEMU is only able to maximally allocate 2047MB RAM on 32bit
            systems.
          '';
        }
        {
          assertion = cfg.boot.initrd != options.virtualisation.boot.initrd.default -> cfg.boot.direct.enable;
          message = ''
            You changed the default of `virtualisation.boot.initrd` but you
            are not using direct boot. This initrd will not be used in your
            current boot configuration.

            To make this warning go away, leave `virtualisation.boot.initrd`
            unchanged or enable direct boot.
          '';
        }
      ];


    virtualisation.qemu.options =
      let
        mkKeyValue = lib.generators.mkKeyValueDefault { } "=";
        mkQemuOptions = options: lib.concatStringsSep "," (lib.mapAttrsToList mkKeyValue options);

        blockDeviceOptions =
          let
            f = name: options:
              let
                blockdevOptions = mkQemuOptions (options.extraBlockdevOptions // {
                  "node-name" = name;
                  "file.driver" = "file";
                  "file.filename" = options.file;
                });
                deviceOptions = mkQemuOptions (options.extraDeviceOptions // {
                  "drive" = name;
                });
              in
              [
                "-blockdev ${blockdevOptions}"
                "-device virtio-blk-pci,${deviceOptions}"
              ];
          in
          lib.mapAttrsToList f cfg.qemu.blockDevices;

        fsDeviceOptions =
          let
            f = name: options:
              let
                fsdevOptions = mkQemuOptions {
                  "path" = options.path;
                  "security_model" = "none";
                  "id" = name;
                };
                deviceOptions = mkQemuOptions {
                  "fsdev" = name;
                  "mount_tag" = name;
                };
              in
              [
                "-fsdev local,${fsdevOptions}"
                "-device virtio-9p-pci,${deviceOptions}"
              ];
          in
          lib.mapAttrsToList f cfg.qemu.fsDevices;

        networkingOptions =
          let
            forwardingOptions = lib.flip lib.concatMapStrings cfg.networking.forwardPorts
              ({ proto, from, host, guest }:
                if from == "host"
                then "hostfwd=${proto}:${host.address}:${toString host.port}-" +
                  "${guest.address}:${toString guest.port},"
                else "'guestfwd=${proto}:${guest.address}:${toString guest.port}-" +
                  "cmd:${pkgs.netcat}/bin/nc ${host.address} ${toString host.port}',"
              );
            restrictNetworkOption = lib.optionalString cfg.networking.restrict "restrict=on,";
          in
          [
            "-netdev user,id=user.0,${forwardingOptions}${restrictNetworkOption}\"$QEMU_NET_OPTS\""
            "-net nic,netdev=user.0,model=virtio"
          ];
      in
      lib.mkMerge [
        # Always included
        [
          "-device virtio-rng-pci"
          "-device virtio-keyboard"
        ]
        blockDeviceOptions
        fsDeviceOptions
        networkingOptions

        (lib.mkIf pkgs.stdenv.hostPlatform.isx86 [
          "-usb"
          "-device usb-tablet,bus=usb-bus.0"
        ])
        (lib.mkIf pkgs.stdenv.hostPlatform.isAarch [
          "-device virtio-gpu-pci"
          "-device usb-ehci,id=usb0"
          "-device usb-kbd"
          "-device usb-tablet"
        ])
        (
          let
            kernelParams = [
              config.boot.kernelParams
              "init=${config.system.build.toplevel}/init"
              "$QEMU_KERNEL_PARAMS"
            ];
          in
          lib.mkIf cfg.boot.direct [
            "-kernel ${config.system.build.toplevel}/kernel"
            "-initrd ${cfg.boot.initrd}"
            ''-append "${toString kernelParams}"''
          ]
        )
        (lib.mkIf cfg.firmware.efi.enable [
          "-drive if=pflash,format=raw,unit=0,readonly=on,file=${cfg.firmware.efi.firmware}"
          "-drive if=pflash,format=raw,unit=1,readonly=off,file=$NIX_EFI_VARS"
        ])
        (lib.mkIf (cfg.firmware.bios != null) [
          "-bios ${cfg.firmware.bios}/bios.bin"
        ])
        (lib.mkIf (!cfg.graphics) [
          "-nographic"
        ])
      ];


    system.build.vm =
      let
        startVM = ''
          #! ${hostPkgs.runtimeShell}

          export PATH=${lib.makeBinPath [ hostPkgs.coreutils ]}''${PATH:+:}$PATH

          set -e

          # Create a directory for storing temporary data of the running VM.
          if [ -z "$TMPDIR" ] || [ -z "$USE_TMPDIR" ]; then
              TMPDIR=$(mktemp -d nix-vm.XXXXXXXXXX --tmpdir)
          fi

          cd "$TMPDIR"

          ${lib.optionalString cfg.firmware.efi.enable ''
            NIX_EFI_VARS=$(readlink -f "''${NIX_EFI_VARS:-${cfg.firmware.efi.variables}}")
          ''}

          exec ${qemu-common.qemuBinary qemu} \
              -name ${config.system.name} \
              -m ${toString cfg.memorySize} \
              -smp ${toString cfg.cores} \
              ${lib.concatStringsSep " \\\n    " cfg.qemu.options} \
              $QEMU_OPTS \
              "$@"
        '';
      in
      hostPkgs.runCommand
        "nixos-vm"
        {
          preferLocalBuild = true;
          meta.mainProgram = "run-${config.system.name}-vm";
        }
        ''
          mkdir -p $out/bin
          ln -s ${config.system.build.toplevel} $out/system
          ln -s ${hostPkgs.writeScript "run-nixos-vm" startVM} $out/bin/run-${config.system.name}-vm
        '';

  };

  meta.maintainers = with lib.maintainers; [ nikstur raitobezarius ];

}
