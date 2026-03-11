{
  config,
  defaultPerms,
  dirOpts,
  fileOpts,
  lib,
  usersCfg,
  ...
}:
let
  inherit (config.thoughtfull) user;
  inherit (lib)
    mapAttrsToList
    mkDefault
    mkOption
    mkOverride
    singleton
    types
    ;
in
{
  options.thoughtfull.impermanence.user = mkOption {
    default = { };
    type = types.submodule (
      { ... }:
      let
        userDefaultPerms = {
          inherit (defaultPerms) mode;
          user = user.name;
          group = usersCfg.${userDefaultPerms.user}.group;
        };
        userFile = types.submodule [
          fileOpts
          {
            parentDirectory = mkDefault userDefaultPerms;
          }
          (
            { config, ... }:
            {
              parentDirectory = {
                directory = dirOf config.file;
              };
            }
          )
        ];
        userDir = types.submodule (
          (singleton dirOpts) ++ (mapAttrsToList (n: v: { ${n} = mkOverride 999 v; }) userDefaultPerms)
        );
      in
      {
        options = {
          directories = mkOption {
            default = [ ];
            description = "Directories to bind mount to persistent storage.";
            example = [
              "Downloads"
              "Music"
              "Pictures"
              "Documents"
              "Videos"
            ];
            type = types.listOf (types.coercedTo types.str (d: { directory = d; }) userDir);
          };
          files = mkOption {
            default = [ ];
            description = "Files that should be stored in persistent storage.";
            example = singleton ".screenrc";
            type = types.listOf (types.coercedTo types.str (f: { file = f; }) userFile);
          };
        };
      }
    );
  };
}
