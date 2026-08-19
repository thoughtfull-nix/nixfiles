{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) impermanence user;
  inherit (lib)
    concatMap
    concatStringsSep
    filter
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    optional
    splitString
    types
    unique
    ;

  # environment.persistence's directory/file submodules are strict (no freeformType), so the
  # backup/backupExclude fields added to dirOpts/fileOpts (impermanence/mounts.nix) must be
  # stripped before merging into it.
  stripDir =
    d:
    removeAttrs d [
      "backup"
      "backupExclude"
    ];
  stripFile = f: removeAttrs f [ "backup" ];

  persistentPrefix = "/${impermanence.persistent.name}";
  joinPath =
    parts: "/" + concatStringsSep "/" (filter (s: s != "") (concatMap (p: splitString "/" p) parts));

  directoryExcludes =
    base: entries:
    concatMap (
      d:
      (optional (!d.backup) (joinPath [
        persistentPrefix
        base
        d.directory
      ]))
      ++ (map (
        sub:
        joinPath [
          persistentPrefix
          base
          d.directory
          sub
        ]
      ) (if d.backup then d.backupExclude else [ ]))
    ) entries;
  fileExcludes =
    base: entries:
    map (
      f:
      joinPath [
        persistentPrefix
        base
        f.file
      ]
    ) (filter (f: !f.backup) entries);
in
{
  config = mkIf impermanence.enable {
    environment.persistence."/${impermanence.persistent.name}" = {
      enable = mkDefault true;
      hideMounts = mkDefault true;
      directories = [
        "/etc/NetworkManager/system-connections"
        "/var/lib/NetworkManager"
        "/var/lib/nixos"
        "/var/lib/systemd/backlight"
        "/var/lib/systemd/coredump"
        "/var/lib/systemd/rfkill"
        "/var/log"
        {
          directory = "/var/db/sudo";
          mode = "u=rwx,g=x,o=x";
        }
      ]
      ++ (map stripDir (unique impermanence.directories));
      files = [
        "/etc/machine-id"
      ]
      ++ (map stripFile (unique impermanence.files));
      users.${user.name} = {
        directories = map stripDir (unique impermanence.user.directories);
        files = map stripFile (unique impermanence.user.files);
      };
    };
    # Persist /var/cache across boots so a reboot doesn't leave every cache cold, but keep it out
    # of backups: its contents are disposable and cheaply regenerated. Contributed as a config
    # definition (not the option's `default`) so it merges with, rather than being dropped by,
    # host and module directory definitions.
    thoughtfull.impermanence.directories = [
      {
        directory = "/var/cache";
        backup = false;
      }
    ];
    fileSystems."/${impermanence.persistent.name}".neededForBoot = mkDefault true;
    services.btrfs.autoScrub.enable = mkDefault true;
    services.restic.thoughtfull = {
      paths = [ persistentPrefix ];
      exclude =
        (directoryExcludes "" (unique impermanence.directories))
        ++ (directoryExcludes user.home (unique impermanence.user.directories))
        ++ (fileExcludes "" (unique impermanence.files))
        ++ (fileExcludes user.home (unique impermanence.user.files));
    };
  };
  imports = [
    (import ./impermanence/mounts.nix {
      inherit config lib;
      locationCfg = config.environment.persistence."/${impermanence.persistent.name}";
      usersCfg = config.users.users;
    })
    (import ./impermanence/gpt.nix {
      inherit config lib pkgs;
    })
    (import ./impermanence/rollback.nix {
      inherit
        config
        lib
        pkgs
        ;
    })
  ];
  options.thoughtfull.impermanence = {
    disko = {
      boot = {
        mountOptions = mkOption {
          default = [ "umask=0077" ];
          type = types.listOf types.str;
        };
        size = mkOption {
          description = "Size of the EFI system partition. Use 1G for a laptop or desktop; 512M if space is tight.";
          type = types.str;
        };
      };
      enable = mkEnableOption "disko" // {
        default = impermanence.enable;
      };
      encrypted.device = mkOption {
        description = "Block device to partition and encrypt. Run `lsblk` or `ls /dev/disk/by-id/` to identify the target drive, e.g. \"/dev/nvme0n1\".";
        type = types.str;
      };
      nix.mountOptions = mkOption {
        default = [
          "compress=zstd"
          "noatime"
        ];
        type = types.listOf types.str;
      };
      persistent = {
        mountOptions = mkOption {
          default = [
            "compress=zstd"
            "noatime"
          ];
          type = types.listOf types.str;
        };
        mountPoint = mkOption {
          default = "/${impermanence.persistent.name}";
          type = types.str;
        };
      };
      root = {
        name = mkOption {
          default = "root";
          type = types.str;
        };
        mountOptions = mkOption {
          default = [
            "compress=zstd"
            "noatime"
          ];
          type = types.listOf types.str;
        };
      };
      snapshots = {
        mountOptions = mkOption {
          default = [
            "compress=zstd"
            "ro"
          ];
          type = types.listOf types.str;
        };
        mountPoint = mkOption {
          default = "/${impermanence.snapshots.name}";
          type = types.str;
        };
      };
      swap.size = mkOption {
        description = "Size of the swap file. Match RAM size to support hibernation (suspend-to-disk); half RAM is sufficient for suspend-to-RAM only. E.g. \"64G\" for a 64 GB machine that needs hibernation.";
        type = types.str;
      };
    };
    enable = mkEnableOption "impermanence" // {
      default = true;
    };
    encrypted.name = mkOption {
      default = "encrypted";
      type = types.str;
    };
    persistent.name = mkOption {
      default = "persistent";
      type = types.str;
    };
    snapshots.name = mkOption {
      default = "snapshots";
      type = types.str;
    };
  };
}
