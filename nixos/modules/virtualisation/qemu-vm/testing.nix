# This module creates a virtual machine from the NixOS configuration tailor
# made for the testing use-case. By default, the Nix store is shared read-only
# with the host, which makes (re)building VMs very efficient.

{ config, lib, pkgs, options, ... }:

with lib;

let

  qemu-common = import ../../lib/qemu-common.nix { inherit lib pkgs; };

  cfg = config.virtualisation;

  opt = options.virtualisation;

  qemu = cfg.qemu.package;

  hostPkgs = cfg.host.pkgs;

  selectPartitionTableLayout = { useEFIBoot, useDefaultFilesystems }:
    if useDefaultFilesystems then
      if useEFIBoot then "efi" else "legacy"
    else "none";

  # Shell script to start the VM.
  startVM = ''
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

    ${lib.optionalString (cfg.useNixStoreImage)
      (if cfg.writableStore then ''
        # Create a writable copy/snapshot of the store image.
        ${qemu}/bin/qemu-img create -f qcow2 -F qcow2 -b ${storeImage}/nixos.qcow2 "$TMPDIR"/store.img
      '' else ''
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

    ${lib.optionalString cfg.useHostCerts ''
      mkdir -p "$TMPDIR/certs"
      if [ -e "$NIX_SSL_CERT_FILE" ]; then
        cp -L "$NIX_SSL_CERT_FILE" "$TMPDIR"/certs/ca-certificates.crt
      else
        echo \$NIX_SSL_CERT_FILE should point to a valid file if virtualisation.useHostCerts is enabled.
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
  options.virtualisation = {

    diskSize = mkOption {
      type = types.nullOr types.ints.positive;
      default = 1024;
      description = lib.mdDoc ''
        The disk size in megabytes of the virtual machine.
      '';
    };

    diskImage = mkOption {
      type = types.nullOr types.str;
      default = "./${config.system.name}.qcow2";
      defaultText = literalExpression ''"./''${config.system.name}.qcow2"'';
      description = lib.mdDoc ''
        Path to the disk image containing the root filesystem.
        The image will be created on startup if it does not
        exist.

        If null, a tmpfs will be used as the root filesystem and
        the VM's state will not be persistent.
      '';
    };

    rootDevice = lib.mkOption {
      type = types.nullOr types.path;
      default = "/dev/disk/by-label/${rootFilesystemLabel}";
      defaultText = literalExpression ''/dev/disk/by-label/${rootFilesystemLabel}'';
      example = "/dev/disk/by-label/nixos";
      description = lib.mdDoc ''
        The path (inside the VM) to the device containing the root filesystem.
      '';
    };

    bootLoaderDevice = lib.mkOption {
      type = types.path;
      default = "/dev/disk/by-id/virtio-${rootDriveSerialAttr}";
      defaultText = literalExpression ''/dev/disk/by-id/virtio-${rootDriveSerialAttr}'';
      example = "/dev/disk/by-id/virtio-boot-loader-device";
      description = lib.mdDoc ''
        The path (inside th VM) to the device to boot from when legacy booting.
      '';
    };

    bootPartition = lib.mkOption {
      type = types.nullOr types.path;
      default = if cfg.useEFIBoot then "/dev/disk/by-label/${espFilesystemLabel}" else null;
      defaultText = literalExpression ''if cfg.useEFIBoot then "/dev/disk/by-label/${espFilesystemLabel}" else null'';
      example = "/dev/disk/by-label/esp";
      description = lib.mdDoc ''
        The path (inside the VM) to the device containing the EFI System Partition (ESP).

        If you are *not* booting from a UEFI firmware, this value is, by
        default, `null`. The ESP is mounted under `/boot`.
      '';
    };

    useBootLoader = lib.mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc ''
        Use a boot loader to boot the system.
        This allows, among other things, testing the boot loader.

        If disabled, the kernel and initrd are directly booted,
        forgoing any bootloader.
      '';
    };


    additionalPaths = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = lib.mdDoc ''
        A list of paths whose closure should be made available to
        the VM.
      '';
    };

    useHostCerts = lib.mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc ''
        If enabled, when `NIX_SSL_CERT_FILE` is set on the host,
        pass the CA certificates from the host to the VM.
      '';
    };


  };

  config = {

    warnings = optional
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

    security.pki.installCACerts = mkIf cfg.useHostCerts false;

    virtualisation = {

      additionalPaths = [ config.system.build.toplevel ];

      images = lib.mkMerge [
        ({
          root = {
            file = ''"$NIX_DISK_IMAGE"'';
            format = "";
            bootindex = 1;
            serialAttr = rootDriveSerialAttr;
          };
        })
        (lib.mkIf cfg.store.image {
          nix-store = {
            file = ''"$TMPDIR"/store.img'';
            format = "";
            bootindex = 2;
          };
        })
      ];

      sharedDirectories = {
        nix-store = lib.mkIf cfg.mountHostNixStore {
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

      qemu.drives = lib.mkMerge [
        (lib.mkIf (cfg.diskImage != null) [{
          name = "root";
          file = ''"$NIX_DISK_IMAGE"'';
          driveExtraOpts.cache = "writeback";
          driveExtraOpts.werror = "report";
          deviceExtraOpts.bootindex = "1";
          deviceExtraOpts.serial = rootDriveSerialAttr;
        }])
        (lib.mkIf cfg.useNixStoreImage [{
          name = "nix-store";
          file = ''"$TMPDIR"/store.img'';
          deviceExtraOpts.bootindex = "2";
          driveExtraOpts.format = if cfg.writableStore then "qcow2" else "raw";
        }])
      ];
    };


    fileSystems = {
      "/" = lib.mkIf cfg.useDefaultFilesystems (if cfg.diskImage == null then {
        device = "tmpfs";
        fsType = "tmpfs";
      } else {
        device = cfg.rootDevice;
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
      "/boot" = lib.mkIf (cfg.useBootLoader && cfg.bootPartition != null) {
        device = cfg.bootPartition;
        fsType = "vfat";
        noCheck = true; # fsck fails on a r/o filesystem
      };
    };


  }
