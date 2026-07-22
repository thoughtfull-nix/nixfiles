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

  # Stub thoughtfull.impermanence.directories for tests that check whether a
  # module appends to the system-level persistence list without importing the
  # full impermanence module.
  impermanenceDirectories =
    { lib, ... }:
    {
      options.thoughtfull.impermanence.directories = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
      };
    };

  # Stub thoughtfull.impermanence.user.{files,directories} for tests that
  # check per-user persistence lists without importing the full impermanence
  # module.
  impermanenceUser =
    { lib, ... }:
    {
      options.thoughtfull.impermanence.user = {
        files = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        directories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };
    };
}
