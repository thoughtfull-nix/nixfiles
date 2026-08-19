# Common NixOS module stubs shared across tests.
#
# Each attribute is a NixOS module function suitable for use in `imports`.
# Stubs satisfy option-type requirements of their respective upstream modules
# without pulling in the real implementation (activation scripts, heavy
# dependencies, hardware-specific drivers, etc.).
{
  # Stub the agenix `age.secrets` option.  Modules that declare secret paths
  # via `age.secrets.<name>` depend on this option being present; the real
  # agenix activation scripts need a live SSH identity to decrypt, which is not
  # available in test VMs.
  ageSecrets =
    { lib, ... }:
    {
      options.age.secrets = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                file = lib.mkOption { type = lib.types.path; };
                mode = lib.mkOption {
                  type = lib.types.str;
                  default = "0400";
                };
                path = lib.mkOption {
                  type = lib.types.str;
                  default = "/run/agenix/${name}";
                };
              };
            }
          )
        );
      };
    };

  # Stub thoughtfull.graphical.enable for tests that need to branch on the
  # graphical flag without importing nixosModules/graphical.nix (which pulls in
  # a large dependency tree).
  graphicalEnable =
    { lib, ... }:
    {
      options.thoughtfull.graphical.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };

  # Stub thoughtfull.user.authorizedKeyFiles for tests that need the
  # committed login SSH key files without importing the full user.nix module
  # (accounts-daemon, icons, hashed passwords, etc.). Points at the real
  # committed files so tests exercise genuine nix store paths.
  userAuthorizedKeyFiles =
    { lib, ... }:
    {
      options.thoughtfull.user.authorizedKeyFiles = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [
          ../nixosModules/user/ypa766/id_ed25519_sk_rk_auth_technosophist.pub
          ../nixosModules/user/ypc940/id_ed25519_sk_rk_auth_technosophist.pub
        ];
      };
    };

  # Stub thoughtfull.impermanence.{directories,user.{files,directories},
  # persistent.name,snapshots.name,encrypted.name,disko.snapshots.mountPoint}
  # for tests that check persistence lists (or, for the other options, the
  # btrfs subvolume paths and device minecraft-server.nix's worldExport
  # derives) without importing the full impermanence module. persistent.name,
  # snapshots.name, encrypted.name, and disko.snapshots.mountPoint all
  # default to the same values the real module does, so tests that don't
  # care about them still see production-realistic paths.
  impermanence =
    { lib, ... }:
    {
      options.thoughtfull.impermanence = {
        directories = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };
        disko.snapshots.mountPoint = lib.mkOption {
          type = lib.types.str;
          default = "/snapshots";
        };
        encrypted.name = lib.mkOption {
          type = lib.types.str;
          default = "encrypted";
        };
        persistent.name = lib.mkOption {
          type = lib.types.str;
          default = "persistent";
        };
        snapshots.name = lib.mkOption {
          type = lib.types.str;
          default = "snapshots";
        };
        user = {
          files = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          directories = lib.mkOption {
            # anything (not str) because directory entries may be attrsets
            # (e.g. { directory = ".m2/repository"; backup = false; }).
            type = lib.types.listOf lib.types.anything;
            default = [ ];
          };
        };
      };
    };
}
