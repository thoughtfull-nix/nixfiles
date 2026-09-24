# Lightweight nix eval check (not a VM boot) for nixosModules/postgresql.nix.
#
# The module keys off services.postgresql.enable and, when set, wires the
# datadir into this repo's impermanence + restic model: /var/lib/postgresql is
# persisted across the stateless root but EXCLUDED from restic (a file-level
# copy of a running datadir isn't crash-consistent; per-database pg_dump is the
# real backup). It also registers postgresql for failure monitoring. When
# PostgreSQL is off the module contributes nothing.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  monitoringServicesStub =
    { lib, ... }:
    {
      options.thoughtfull.monitoring.services = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

  mkEval =
    extraModule:
    (nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        ../nixosModules/postgresql.nix
        stubs.impermanence
        monitoringServicesStub
        extraModule
      ];
    }).config;

  enabledEval = mkEval ({ ... }: { services.postgresql.enable = true; });
  disabledEval = mkEval ({ ... }: { });

  dirs = enabledEval.thoughtfull.impermanence.directories;
  pgDir = lib.findFirst (d: (d.directory or null) == "/var/lib/postgresql") null dirs;

  checks = [
    {
      name = "enabled: /var/lib/postgresql is persisted as postgres";
      ok = pgDir != null && (pgDir.user or null) == "postgres" && (pgDir.mode or null) == "0700";
    }
    {
      name = "enabled: the datadir is excluded from restic";
      ok = pgDir != null && (pgDir.backup or true) == false;
    }
    {
      name = "enabled: postgresql is registered for failure monitoring";
      ok = lib.elem "postgresql" enabledEval.thoughtfull.monitoring.services;
    }
    {
      name = "disabled: nothing persisted when PostgreSQL is off";
      ok = disabledEval.thoughtfull.impermanence.directories == [ ];
    }
    {
      name = "disabled: nothing monitored when PostgreSQL is off";
      ok = disabledEval.thoughtfull.monitoring.services == [ ];
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    postgresql test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "postgresql-test" { } "touch $out"
