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

    bootLoaderDevice = mkOption {
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
      description =
        lib.mdDoc ''
          The path (inside the VM) to the device containing the EFI System Partition (ESP).

          If you are *not* booting from a UEFI firmware, this value is, by
          default, `null`. The ESP is mounted under `/boot`.
        '';
    };

    rootDevice = lib.mkOption {
      type = types.nullOr types.path;
      default = "/dev/disk/by-label/${rootFilesystemLabel}";
      defaultText = literalExpression ''/dev/disk/by-label/${rootFilesystemLabel}'';
      example = "/dev/disk/by-label/nixos";
      description =
        lib.mdDoc ''
          The path (inside the VM) to the device containing the root filesystem.
        '';
    };

    useBootLoader = lib.mkOption {
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


    additionalPaths = lib.mkOption {
      type = types.listOf types.path;
      default = [ ];
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

    useHostCerts = lib.mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc ''
        If enabled, when `NIX_SSL_CERT_FILE` is set on the host,
        pass the CA certificates from the host to the VM.
      '';
    };


    store = {

      writable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.mountHostNixStore;
        defaultText = literalExpression "cfg.mountHostNixStore";
        description = lib.mdDoc ''
          If enabled, the Nix store in the VM is made writable by
          layering an overlay filesystem on top of the host's Nix
          store.

          By default, this is enabled if you mount a host Nix store.
        '';
      };

      tmpfs = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = lib.mdDoc ''
          Use a tmpfs for the writable store instead of writing to the VM's
          own filesystem.
        '';
      };

      image = lib.mkOption {
        type = lib.types.bool;
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

      mountHostNixStore = lib.mkOption {
        type = lib.types.bool;
        default = !cfg.useNixStoreImage && !cfg.useBootLoader;
        defaultText = literalExpression "!cfg.useNixStoreImage && !cfg.useBootLoader";
        description = lib.mdDoc ''
          Mount the host Nix store as a 9p mount.
        '';
      };
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

      images = {
        root = {
          file = ''"$NIX_DISK_IMAGE"'';
        };
      };

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


    boot.initrd = {

      availableKernelModules = lib.optional cfg.writableStore "overlay";

      postMountCommands = lib.mkIf (!config.boot.initrd.systemd.enable && cfg.writableStore) ''
        echo "mounting overlay filesystem on /nix/store..."
        mkdir -p -m 0755 $targetRoot/nix/.rw-store/store $targetRoot/nix/.rw-store/work $targetRoot/nix/store
        mount -t overlay overlay $targetRoot/nix/store \
          -o lowerdir=$targetRoot/nix/.ro-store,upperdir=$targetRoot/nix/.rw-store/store,workdir=$targetRoot/nix/.rw-store/work || fail
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
  }
