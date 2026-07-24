{
  config,
  lib,
  locationCfg,
  usersCfg,
  ...
}:
let
  inherit (lib)
    mapAttrs
    mapAttrsToList
    mkDefault
    mkOption
    singleton
    types
    ;
  defaultPerms = {
    mode = "0755";
    user = "root";
    group = "root";
  };
  dirOpts.options = {
    backup = mkOption {
      default = true;
      description = ''
        Whether this directory's contents should be included in restic backups. Set to false to
        persist the directory across boots without backing it up (for example, a package manager
        download cache).
      '';
      type = types.bool;
    };
    backupExclude = mkOption {
      default = [ ];
      description = ''
        Paths relative to `directory` to exclude from restic backups, even though the directory
        itself is backed up. Ignored if `backup` is false. Useful when a persisted directory has a
        known cache subdirectory that shouldn't be backed up (for example, a game's asset cache).
      '';
      example = [ "cache" ];
      type = types.listOf types.str;
    };
    directory = mkOption {
      description = "The path to the directory.";
      type = types.str;
    };
    group = mkOption {
      description = ''
        If the directory doesn't exist in persistent storage it will be created and owned by the
        group specified by this option.
      '';
      type = types.str;
    };
    hideMount = mkOption {
      default = locationCfg.hideMounts;
      defaultText = ''
        environment.persistence."/''${thoughtfull.impermanence.persistent.name}".hideMounts
      '';
      example = true;
      description = "Whether to hide bind mounts from showing up as mounted drives.";
      type = types.bool;
    };
    mode = mkOption {
      description = ''
        If the directory doesn't exist in persistent storage it will be created with the mode
        specified by this option.
      '';
      example = "0700";
      type = types.str;
    };
    user = mkOption {
      description = ''
        If the directory doesn't exist in persistent storage it will be created and owned by the
        user specified by this option.
      '';
      type = types.str;
    };
  };
  fileOpts.options = {
    backup = mkOption {
      default = true;
      description = ''
        Whether this file should be included in restic backups. Set to false to persist the file
        across boots without backing it up.
      '';
      type = types.bool;
    };
    file = mkOption {
      description = "The path to the file.";
      type = types.str;
    };
    # backup/backupExclude describe restic handling for the directory/file itself; they have no
    # meaningful effect on the parent directory created to hold it, so they're excluded here
    # rather than mirrored in a way that looks configurable but silently does nothing.
    parentDirectory =
      mapAttrs (_: x: if x._type or null == "option" then x // { internal = true; } else x)
        (
          removeAttrs dirOpts.options [
            "backup"
            "backupExclude"
          ]
        );
  };
  rootFile = types.submodule [
    fileOpts
    (
      { config, ... }:
      {
        parentDirectory = mkDefault (
          defaultPerms
          // {
            directory = dirOf config.file;
          }
        );
      }
    )
  ];
  rootDir = types.submodule (
    (singleton dirOpts) ++ (mapAttrsToList (n: v: { ${n} = mkDefault v; }) defaultPerms)
  );
in
{
  imports = [
    (import ./user-mounts.nix {
      inherit
        config
        defaultPerms
        dirOpts
        fileOpts
        lib
        usersCfg
        ;
    })
  ];
  options.thoughtfull.impermanence = {
    directories = mkOption {
      default = [ ];
      description = "Directories to bind mount to persistent storage.";
      example = [
        "/etc/NetworkManager/system-connections"
        "/var/lib/nixos"
        "/var/lib/systemd/backlight"
        "/var/lib/systemd/coredump"
        "/var/lib/systemd/rfkill"
        "/var/log"
      ];
      type = types.listOf (types.coercedTo types.str (d: { directory = d; }) rootDir);
    };
    files = mkOption {
      default = [ ];
      description = "Files that should be stored in persistent storage.";
      example = [
        "/etc/machine-id"
        "/etc/nix/id_rsa"
      ];
      type = types.listOf (types.coercedTo types.str (f: { file = f; }) rootFile);
    };
  };
}
