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
    file = mkOption {
      description = "The path to the file.";
      type = types.str;
    };
    parentDirectory = mapAttrs (
      _: x: if x._type or null == "option" then x // { internal = true; } else x
    ) dirOpts.options;
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
        "/var/lib/systemd/coredump"
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
