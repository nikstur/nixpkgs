# This module creates a virtual machine from the NixOS configuration.
# Building the `config.system.build.vm' attribute gives you a command
# that starts a KVM/QEMU VM running the NixOS configuration defined in
# `config'. By default, the Nix store is shared read-only with the
# host, which makes (re)building VMs very efficient.

{ config, lib, pkgs, options, ... }:

with lib;

let

  cfg = config.virtualisation;

  opt = options.virtualisation;

  selectPartitionTableLayout = { useEFIBoot, useDefaultFilesystems }:
    if useDefaultFilesystems then
      if useEFIBoot then "efi" else "legacy"
    else "none";

  # Shell script to start the VM.
  startVM =
    ''
      #! ${hostPkgs.runtimeShell}

      export PATH=${makeBinPath [ hostPkgs.coreutils ]}''${PATH:+:}$PATH

      set -e

      # Create an empty ext4 filesystem image. A filesystem image does not
      # contain a partition table but just a filesystem.
      createEmptyFilesystemImage() {
        local name=$1
        local size=$2
        local temp=$(mktemp)
        ${qemu}/bin/qemu-img create -f raw "$temp" "$size"
        ${hostPkgs.e2fsprogs}/bin/mkfs.ext4 -L ${rootFilesystemLabel} "$temp"
        ${qemu}/bin/qemu-img convert -f raw -O qcow2 "$temp" "$name"
        rm "$temp"
      }

      NIX_DISK_IMAGE=$(readlink -f "''${NIX_DISK_IMAGE:-${toString config.virtualisation.diskImage}}") || test -z "$NIX_DISK_IMAGE"

      if test -n "$NIX_DISK_IMAGE" && ! test -e "$NIX_DISK_IMAGE"; then
          echo "Disk image do not exist, creating the virtualisation disk image..."

          ${if (cfg.useBootLoader && cfg.useDefaultFilesystems) then ''
            # Create a writable qcow2 image using the systemImage as a backing
            # image.

            # CoW prevent size to be attributed to an image.
            # FIXME: raise this issue to upstream.
            ${qemu}/bin/qemu-img create \
              -f qcow2 \
              -b ${systemImage}/nixos.qcow2 \
              -F qcow2 \
              "$NIX_DISK_IMAGE"
          '' else if cfg.useDefaultFilesystems then ''
            createEmptyFilesystemImage "$NIX_DISK_IMAGE" "${toString cfg.diskSize}M"
          '' else ''
            # Create an empty disk image without a filesystem.
            ${qemu}/bin/qemu-img create -f qcow2 "$NIX_DISK_IMAGE" "${toString cfg.diskSize}M"
          ''
          }
          echo "Virtualisation disk image created."
      fi

      # Create a directory for storing temporary data of the running VM.
      if [ -z "$TMPDIR" ] || [ -z "$USE_TMPDIR" ]; then
          TMPDIR=$(mktemp -d nix-vm.XXXXXXXXXX --tmpdir)
      fi

      ${lib.optionalString (cfg.useNixStoreImage)
        (if cfg.writableStore
          then ''
            # Create a writable copy/snapshot of the store image.
            ${qemu}/bin/qemu-img create -f qcow2 -F qcow2 -b ${storeImage}/nixos.qcow2 "$TMPDIR"/store.img
          ''
          else ''
            (
              cd ${builtins.storeDir}
              ${hostPkgs.erofs-utils}/bin/mkfs.erofs \
                --force-uid=0 \
                --force-gid=0 \
                -L ${nixStoreFilesystemLabel} \
                -U eb176051-bd15-49b7-9e6b-462e0b467019 \
                -T 0 \
                --exclude-regex="$(
                  <${hostPkgs.closureInfo { rootPaths = [ config.system.build.toplevel regInfo ]; }}/store-paths \
                    sed -e 's^.*/^^g' \
                  | cut -c -10 \
                  | ${hostPkgs.python3}/bin/python ${./includes-to-excludes.py} )" \
                "$TMPDIR"/store.img \
                . \
                </dev/null >/dev/null
            )
          ''
        )
      }

      # Create a directory for exchanging data with the VM.
      mkdir -p "$TMPDIR/xchg"

      ${lib.optionalString cfg.useHostCerts
      ''
        mkdir -p "$TMPDIR/certs"
        if [ -e "$NIX_SSL_CERT_FILE" ]; then
          cp -L "$NIX_SSL_CERT_FILE" "$TMPDIR"/certs/ca-certificates.crt
        else
          echo \$NIX_SSL_CERT_FILE should point to a valid file if virtualisation.useHostCerts is enabled.
        fi
      ''}

      ${lib.optionalString cfg.useEFIBoot
      ''
        # Expose EFI variables, it's useful even when we are not using a bootloader (!).
        # We might be interested in having EFI variable storage present even if we aren't booting via UEFI, hence
        # no guard against `useBootLoader`.  Examples:
        # - testing PXE boot or other EFI applications
        # - directbooting LinuxBoot, which `kexec()s` into a UEFI environment that can boot e.g. Windows
        NIX_EFI_VARS=$(readlink -f "''${NIX_EFI_VARS:-${config.system.name}-efi-vars.fd}")
        # VM needs writable EFI vars
        if ! test -e "$NIX_EFI_VARS"; then
        ${if cfg.useBootLoader then
            # We still need the EFI var from the make-disk-image derivation
            # because our "switch-to-configuration" process might
            # write into it and we want to keep this data.
            ''cp ${systemImage}/efi-vars.fd "$NIX_EFI_VARS"''
            else
            ''cp ${cfg.efi.variables} "$NIX_EFI_VARS"''
          }
          chmod 0644 "$NIX_EFI_VARS"
        fi
      ''}

      cd "$TMPDIR"

      ${lib.optionalString (cfg.emptyDiskImages != []) "idx=0"}
      ${flip concatMapStrings cfg.emptyDiskImages (size: ''
        if ! test -e "empty$idx.qcow2"; then
            ${qemu}/bin/qemu-img create -f qcow2 "empty$idx.qcow2" "${toString size}M"
        fi
        idx=$((idx + 1))
      '')}

      # Start QEMU.
    '';


  regInfo = hostPkgs.closureInfo { rootPaths = config.virtualisation.additionalPaths; };

  # Use well-defined and persistent filesystem labels to identify block devices.
  rootFilesystemLabel = "nixos";
  espFilesystemLabel = "ESP"; # Hard-coded by make-disk-image.nix
  nixStoreFilesystemLabel = "nix-store";

  # The root drive is a raw disk which does not necessarily contain a
  # filesystem or partition table. It thus cannot be identified via the typical
  # persistent naming schemes (e.g. /dev/disk/by-{label, uuid, partlabel,
  # partuuid}. Instead, supply a well-defined and persistent serial attribute
  # via QEMU. Inside the running system, the disk can then be identified via
  # the /dev/disk/by-id scheme.
  rootDriveSerialAttr = "root";

  # System image is akin to a complete NixOS install with
  # a boot partition and root partition.
  systemImage = import ../../lib/make-disk-image.nix {
    inherit pkgs config lib;
    additionalPaths = [ regInfo ];
    format = "qcow2";
    onlyNixStore = false;
    label = rootFilesystemLabel;
    partitionTableType = selectPartitionTableLayout { inherit (cfg) useDefaultFilesystems useEFIBoot; };
    installBootLoader = cfg.useBootLoader && cfg.useDefaultFilesystems;
    touchEFIVars = cfg.useEFIBoot;
    diskSize = "auto";
    additionalSpace = "0M";
    copyChannel = false;
    OVMF = cfg.efi.OVMF;
  };

  storeImage = import ../../lib/make-disk-image.nix {
    inherit pkgs config lib;
    additionalPaths = [ regInfo ];
    format = "qcow2";
    onlyNixStore = true;
    label = nixStoreFilesystemLabel;
    partitionTableType = "none";
    installBootLoader = false;
    touchEFIVars = false;
    diskSize = "auto";
    additionalSpace = "0M";
    copyChannel = false;
  };

in

{

  options.vitualisation = {


    msize =
      mkOption {
        type = types.ints.positive;
        default = 16384;
        description =
          lib.mdDoc ''
            The msize (maximum packet size) option passed to 9p file systems, in
            bytes. Increasing this should increase performance significantly,
            at the cost of higher RAM usage.
          '';
      };

    diskSize =
      mkOption {
        type = types.nullOr types.ints.positive;
        default = 1024;
        description =
          lib.mdDoc ''
            The disk size in megabytes of the virtual machine.
          '';
      };

    diskImage =
      mkOption {
        type = types.nullOr types.str;
        default = "./${config.system.name}.qcow2";
        defaultText = literalExpression ''"./''${config.system.name}.qcow2"'';
        description =
          lib.mdDoc ''
            Path to the disk image containing the root filesystem.
            The image will be created on startup if it does not
            exist.

            If null, a tmpfs will be used as the root filesystem and
            the VM's state will not be persistent.
          '';
      };

    emptyDiskImages =
      mkOption {
        type = types.listOf types.ints.positive;
        default = [ ];
        description = lib.mdDoc ''
          Additional disk images to provide to the VM. The value is
          a list of size in megabytes of each disk. These disks are
          writeable by the VM.
        '';
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
      type = types.attrsOf (types.submodule {
        options = {

          source = mkOption {
            type = types.str;
            description = lib.mdDoc "The path of the directory to share, can be a shell variable";
          };

          target = mkOption {
            type = types.path;
            description = lib.mdDoc "The mount point of the directory inside the virtual machine";
          };

        };
      });
    };

    additionalPaths = lib.mkOption {
      type = types.listOf types.path;
      default = [ config.system.build.toplevel ];
      description = lib.mdDoc ''
        A list of paths whose closure should be made available to
        the VM.

        When 9p is used, the closure is registered in the Nix
        database in the VM. All other paths in the host Nix store
        appear in the guest Nix store as well, but are considered
        garbage (because they are not registered in the Nix
        database of the guest).

        When {option}`virtualisation.useNixStoreImage` is
        set, the closure is copied to the Nix store image.
      '';
    };

    useNixStoreImage =
      mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Build and use a disk image for the Nix store, instead of
          accessing the host's one through 9p.

          For applications which do a lot of reads from the store,
          this can drastically improve performance, but at the cost of
          disk space and image build time.

          As an alternative, you can use a bootloader which will provide you
          with a full NixOS system image containing a Nix store and
          avoid mounting the host nix store through
          {option}`virtualisation.mountHostNixStore`.
        '';
      };

    mountHostNixStore =
      mkOption {
        type = types.bool;
        default = !cfg.useNixStoreImage && !cfg.useBootLoader;
        defaultText = literalExpression "!cfg.useNixStoreImage && !cfg.useBootLoader";
        description = lib.mdDoc ''
          Mount the host Nix store as a 9p mount.
        '';
      };

    useBootLoader =
      mkOption {
        type = types.bool;
        default = false;
        description =
          lib.mdDoc ''
            Use a boot loader to boot the system.
            This allows, among other things, testing the boot loader.

            If disabled, the kernel and initrd are directly booted,
            forgoing any bootloader.
          '';
      };

    useHostCerts =
      mkOption {
        type = types.bool;
        default = false;
        description =
          lib.mdDoc ''
            If enabled, when `NIX_SSL_CERT_FILE` is set on the host,
            pass the CA certificates from the host to the VM.
          '';
      };

    writableStore = lib.mkOption {
      type = types.bool;
      default = cfg.mountHostNixStore;
      defaultText = literalExpression "cfg.mountHostNixStore";
      description = lib.mdDoc ''
        If enabled, the Nix store in the VM is made writable by
        layering an overlay filesystem on top of the host's Nix
        store.

        By default, this is enabled if you mount a host Nix store.
      '';
    };

    writableStoreUseTmpfs = lib.mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc ''
        Use a tmpfs for the writable store instead of writing to the VM's
        own filesystem.
      '';
    };


    networking = {

      interfaces = mkOption {
        default = { };
        example = {
          enp1s0.vlan = 1;
        };
        description = lib.mdDoc ''
          Network interfaces to add to the VM.
        '';
        type = with types; attrsOf (submodule {
          options = {

            vlan = mkOption {
              type = types.ints.unsigned;
              description = lib.mdDoc ''
                VLAN to which the network interface is connected.
              '';
            };

            assignIP = mkOption {
              type = types.bool;
              default = false;
              description = lib.mdDoc ''
                Automatically assign an IP address to the network interface using the same scheme as
                virtualisation.vlans.
              '';

            };
          };
        });
      };

      vlans = lib.mkOption {
        type = types.listOf types.ints.unsigned;
        default = if config.virtualisation.interfaces == { } then [ 1 ] else [ ];
        defaultText = lib.literalExpression ''if config.virtualisation.interfaces == {} then [ 1 ] else [ ]'';
        example = [ 1 2 ];
        description = lib.mdDoc ''
          Virtual networks to which the VM is connected.  Each
          number «N» in this list causes
          the VM to have a virtual Ethernet interface attached to a
          separate virtual network on which it will be assigned IP
          address
          `192.168.«N».«M»`,
          where «M» is the index of this VM
          in the list of VMs.
        '';
      };

    };


    qemu = {

      guestAgent.enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = lib.mdDoc ''
          Enable the Qemu guest agent.
        '';
      };

    };

  };

  config = {


    warnings = lib.optional
      (
        cfg.writableStore &&
        cfg.useNixStoreImage &&
        opt.writableStore.highestPrio > lib.modules.defaultOverridePriority
      )
      ''
        You have enabled ${opt.useNixStoreImage} = true,
        without setting ${opt.writableStore} = false.

        This causes a store image to be written to the store, which is
        costly, especially for the binary cache, and because of the need
        for more frequent garbage collection.

        If you really need this combination, you can set ${opt.writableStore}
        explicitly to true, incur the cost and make this warning go away.
        Otherwise, we recommend

        ${opt.writableStore} = false;
      '';


    virtualisation = {

      sharedDirectories = {
        nix-store = mkIf cfg.mountHostNixStore {
          source = builtins.storeDir;
          target = "/nix/store";
        };
        xchg = {
          source = ''"$TMPDIR"/xchg'';
          target = "/tmp/xchg";
        };
        shared = {
          source = ''"''${SHARED_DIR:-$TMPDIR/xchg}"'';
          target = "/tmp/shared";
        };
        certs = mkIf cfg.useHostCerts {
          source = ''"$TMPDIR"/certs'';
          target = "/etc/ssl/certs";
        };
      };

      qemu.drives = mkMerge [
        (mkIf (cfg.diskImage != null) [{
          name = "root";
          file = ''"$NIX_DISK_IMAGE"'';
          driveExtraOpts.cache = "writeback";
          driveExtraOpts.werror = "report";
          deviceExtraOpts.bootindex = "1";
          deviceExtraOpts.serial = rootDriveSerialAttr;
        }])
        (mkIf cfg.useNixStoreImage [{
          name = "nix-store";
          file = ''"$TMPDIR"/store.img'';
          deviceExtraOpts.bootindex = "2";
          driveExtraOpts.format = if cfg.writableStore then "qcow2" else "raw";
        }])
        (imap0
          (idx: _: {
            file = "$(pwd)/empty${toString idx}.qcow2";
            driveExtraOpts.werror = "report";
          })
          cfg.emptyDiskImages)
      ];

    };


    fileSystems =
      let
        mkSharedDir = tag: share:
          {
            name =
              if tag == "nix-store" && cfg.writableStore
              then "/nix/.ro-store"
              else share.target;
            value.device = tag;
            value.fsType = "9p";
            value.neededForBoot = true;
            value.options =
              [ "trans=virtio" "version=9p2000.L" "msize=${toString cfg.msize}" ]
              ++ lib.optional (tag == "nix-store") "cache=loose";
          };
      in
      lib.mkMerge [
        (lib.mapAttrs' mkSharedDir cfg.sharedDirectories)
        {
          "/" = lib.mkIf cfg.useDefaultFilesystems (if cfg.diskImage == null then {
            device = "tmpfs";
            fsType = "tmpfs";
          } else {
            device = "/dev/disk/by-label/${rootFilesystemLabel}";
            fsType = "ext4";
          });
          "/tmp" = lib.mkIf config.boot.tmp.useTmpfs {
            device = "tmpfs";
            fsType = "tmpfs";
            neededForBoot = true;
            # Sync with systemd's tmp.mount;
            options = [ "mode=1777" "strictatime" "nosuid" "nodev" "size=${toString config.boot.tmp.tmpfsSize}" ];
          };
          "/nix/${if cfg.writableStore then ".ro-store" else "store"}" = lib.mkIf cfg.useNixStoreImage {
            device = "/dev/disk/by-label/${nixStoreFilesystemLabel}";
            neededForBoot = true;
            options = [ "ro" ];
          };
          "/nix/.rw-store" = lib.mkIf (cfg.writableStore && cfg.writableStoreUseTmpfs) {
            fsType = "tmpfs";
            options = [ "mode=0755" ];
            neededForBoot = true;
          };
          "/boot" = lib.mkIf cfg.useBootLoader {
            device = "/dev/disk/by-label/${espFilesystemLabel}";
            fsType = "vfat";
            noCheck = true; # fsck fails on a r/o filesystem
          };
        }
      ];


    boot.initrd = {

      availableKernelModules = lib.optional cfg.writableStore "overlay";

      postMountCommands = lib.mkIf (!config.boot.initrd.systemd.enable)
        ''
          # Mark this as a NixOS machine.
          mkdir -p $targetRoot/etc
          echo -n > $targetRoot/etc/NIXOS

          # Fix the permissions on /tmp.
          chmod 1777 $targetRoot/tmp

          mkdir -p $targetRoot/boot

          ${optionalString cfg.writableStore ''
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

    # After booting, register the closure of the paths in
    # `virtualisation.additionalPaths' in the Nix database in the VM.  This
    # allows Nix operations to work in the VM.  The path to the
    # registration file is passed through the kernel command line to
    # allow `system.build.toplevel' to be included.  (If we had a direct
    # reference to ${regInfo} here, then we would get a cyclic
    # dependency.)
    boot.postBootCommands = lib.mkIf config.nix.enable ''
      if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
        ${config.nix.package.out}/bin/nix-store --load-db < ''${BASH_REMATCH[1]}
      fi
    '';

    security.pki.installCACerts = lib.mkIf cfg.useHostCerts false;

    services = {
      # Don't run ntpd in the guest. It should get the correct time from KVM.
      timesyncd.enable = false;

      qemuGuest.enable = cfg.qemu.guestAgent.enable;
    };

    networking = {
      # Speed up booting by not waiting for ARP.
      dhcpcd.extraConfig = "noarp";

      usePredictableInterfaceNames = false;
    };

    system.requiredKernelConfig = with config.lib.kernelConfig;
      [
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
      ] ++ optionals (!cfg.graphics) [
        (isYes "SERIAL_8250_CONSOLE")
        (isYes "SERIAL_8250")
      ] ++ optionals (cfg.writableStore) [
        (isEnabled "OVERLAY_FS")
      ];
  };
}
