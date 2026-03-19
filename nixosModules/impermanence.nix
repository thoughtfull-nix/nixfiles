{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) impermanence user;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;
in
{
  config = mkIf impermanence.enable (mkMerge [
    {
      environment.persistence."/${impermanence.persistent.name}" = {
        enable = mkDefault true;
        hideMounts = mkDefault true;
        directories = [
          "/etc/NetworkManager/system-connections"
          "/var/lib/nixos"
          "/var/lib/systemd/coredump"
          "/var/log"
          {
            directory = "/var/db/sudo";
            mode = "u=rwx,g=x,o=x";
          }
        ]
        ++ impermanence.directories;
        files = [
          "/etc/machine-id"
        ]
        ++ impermanence.files;
        users.${user.name} = (impermanence.user);
      };
      fileSystems."/${impermanence.persistent.name}".neededForBoot = mkDefault true;
      services.btrfs.autoScrub.enable = mkDefault true;
    }
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
  ]);
  imports = [
    (import ./impermanence/mounts.nix {
      inherit config lib;
      locationCfg = config.environment.persistence."/${impermanence.persistent.name}";
      usersCfg = config.users.users;
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
          default = "512M";
          type = types.str;
        };
      };
      enable = mkEnableOption "disko" // {
        default = impermanence.enable;
      };
      encrypted.device = mkOption {
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
        default = "4G";
        type = types.str;
      };
    };
    enable = mkEnableOption "impermanence";
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
