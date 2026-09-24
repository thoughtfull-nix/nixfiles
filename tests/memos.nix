# Lightweight nix eval check (not a VM boot) for nixosModules/memos.nix.
#
# thoughtfull.memos wraps the upstream services.memos for this repo's
# impermanence + restic model. Under test is the eval-time wiring: the instance
# settings (localhost:5230 behind a TLS-terminating proxy, the public instance
# URL, the PostgreSQL driver + peer-socket DSN), local PostgreSQL provisioning,
# and persistence of /var/lib/memos (persisted AND backed up). Persisting the
# PostgreSQL datadir (and excluding it from restic) is owned by
# nixosModules/postgresql.nix and asserted in tests/postgresql.nix. Booting
# Memos + PostgreSQL for real is upstream's concern; here we only assert the
# configuration this module derives.
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
        ../nixosModules/memos.nix
        stubs.impermanence
        monitoringServicesStub
        extraModule
      ];
    }).config;

  enabledEval = mkEval ({ ... }: { services.memos.enable = true; });

  disabledEval = mkEval ({ ... }: { });

  settings = enabledEval.services.memos.settings;
  postgresql = enabledEval.services.postgresql;
  dirs = enabledEval.thoughtfull.impermanence.directories;
  memosDir = lib.findFirst (d: (d.directory or null) == "/var/lib/memos") null dirs;

  checks = [
    {
      name = "enabled: binds localhost:5230 (TLS terminated upstream by the proxy)";
      ok = settings.MEMOS_ADDR == "127.0.0.1" && settings.MEMOS_PORT == "5230";
    }
    {
      name = "enabled: public instance URL is the notes subdomain over https";
      ok = settings.MEMOS_INSTANCE_URL == "https://notes.thoughtfull.systems";
    }
    {
      name = "enabled: uses the PostgreSQL driver over the peer-authenticated socket";
      ok =
        settings.MEMOS_DRIVER == "postgres"
        && settings.MEMOS_DSN == "user=memos host=/run/postgresql dbname=memos sslmode=disable";
    }
    {
      name = "enabled: provisions a local memos database owned by the memos role";
      ok =
        postgresql.enable
        && postgresql.ensureDatabases == [ "memos" ]
        && lib.any (u: u.name == "memos" && u.ensureDBOwnership) postgresql.ensureUsers;
    }
    {
      # Must gate on postgresql-setup.service (the unit that creates the memos
      # role), not the bare postgresql.service or postgresql.target.
      name = "enabled: memos is ordered after postgresql-setup.service";
      ok = lib.elem "postgresql-setup.service" enabledEval.systemd.services.memos.after;
    }
    {
      name = "enabled: does not open the firewall (reachable only via the tunnel)";
      ok = !enabledEval.services.memos.openFirewall;
    }
    {
      name = "enabled: the memos database is registered for pg_dump backup";
      ok = enabledEval.services.postgresqlBackup.databases == [ "memos" ];
    }
    {
      # Persisting /var/lib/postgresql (and excluding it from restic) is owned
      # by nixosModules/postgresql.nix now, so it is asserted in that test.
      name = "enabled: /var/lib/memos is persisted as memos and backed up";
      ok = memosDir != null && (memosDir.user or null) == "memos" && (memosDir.backup or true);
    }
    {
      name = "enabled: the memos service is registered for failure monitoring";
      ok = lib.elem "memos" enabledEval.thoughtfull.monitoring.services;
    }
    {
      name = "disabled: nothing persisted when Memos is off";
      ok = disabledEval.thoughtfull.impermanence.directories == [ ];
    }
    {
      name = "disabled: nothing monitored when Memos is off";
      ok = disabledEval.thoughtfull.monitoring.services == [ ];
    }
    {
      name = "disabled: PostgreSQL is not enabled by this module when Memos is off";
      ok = !disabledEval.services.postgresql.enable;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    memos test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "memos-test" { } "touch $out"
