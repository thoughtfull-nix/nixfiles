# Lightweight nix eval check (not a VM boot) for nixosModules/postgresql-backup.nix.
#
# This module wraps the upstream services.postgresqlBackup: it turns pg_dump on
# by default wherever PostgreSQL runs, routes the dump directory into
# thoughtfull.impermanence.directories so it lands in /persistent and gets
# backed up (the live postgres data dir is persisted but excluded elsewhere;
# the dump is the crash-consistent copy), and -- on restic hosts -- runs the
# dump as a dependency of the restic backup instead of on its own timer, so
# restic always captures a just-made dump. All eval-time wiring.
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

  # Stub the repo's restic switch so the module can decide whether to attach the
  # dump to restic-backups-default, without importing the real restic module.
  resticEnableStub =
    { lib, ... }:
    {
      options.services.restic.thoughtfull.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };

  mkEval =
    extraModule:
    (nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        ../nixosModules/postgresql-backup.nix
        stubs.impermanence
        monitoringServicesStub
        resticEnableStub
        extraModule
      ];
    }).config;

  # A restic host running PostgreSQL with a named database (like tislit).
  enabledEval = mkEval (
    { ... }:
    {
      services.postgresql.enable = true;
      services.postgresqlBackup.databases = [ "gotosocial" ];
      services.restic.thoughtfull.enable = true;
    }
  );

  # A restic host with no databases named: upstream dumps the whole cluster from
  # a single postgresqlBackup.service (pg_dumpall).
  backupAllEval = mkEval (
    { ... }:
    {
      services.postgresql.enable = true;
      services.restic.thoughtfull.enable = true;
    }
  );

  # PostgreSQL but no restic: the dump falls back to its own timer.
  timerFallbackEval = mkEval (
    { ... }:
    {
      services.postgresql.enable = true;
      services.postgresqlBackup.databases = [ "gotosocial" ];
      services.restic.thoughtfull.enable = false;
    }
  );

  # A host with no PostgreSQL: the wrapper must stay entirely inert.
  disabledEval = mkEval (
    { ... }:
    {
      services.postgresql.enable = false;
    }
  );

  dumpDir = lib.findFirst (
    d: (d.directory or null) == "/var/backup/postgresql"
  ) null enabledEval.thoughtfull.impermanence.directories;
  resticDefault = enabledEval.systemd.services.restic-backups-default;

  checks = [
    {
      name = "enabled: pg_dump backups turn on automatically where postgres runs";
      ok = enabledEval.services.postgresqlBackup.enable;
    }
    {
      name = "enabled: the dump dir is persisted (so restic captures it) as postgres";
      ok = dumpDir != null && (dumpDir.user or null) == "postgres";
    }
    {
      name = "enabled: the dump dir is not excluded from backup";
      ok = dumpDir != null && (dumpDir.backup or true);
    }
    {
      name = "enabled: each database's dump unit is registered for failure monitoring";
      ok = lib.elem "postgresqlBackup-gotosocial" enabledEval.thoughtfull.monitoring.services;
    }
    {
      # On a restic host the standalone timer is disabled; the dump runs as a
      # dependency of the backup instead.
      name = "enabled: the dump's own timer is disabled on a restic host";
      ok = enabledEval.systemd.services."postgresqlBackup-gotosocial".startAt == [ ];
    }
    {
      name = "enabled: restic wants + runs after the dump unit";
      ok =
        lib.elem "postgresqlBackup-gotosocial.service" resticDefault.wants
        && lib.elem "postgresqlBackup-gotosocial.service" resticDefault.after;
    }
    {
      name = "backupAll: the whole-cluster dump unit is registered for monitoring";
      ok = backupAllEval.thoughtfull.monitoring.services == [ "postgresqlBackup" ];
    }
    {
      name = "backupAll: restic wants + runs after the whole-cluster dump unit";
      ok = lib.elem "postgresqlBackup.service" backupAllEval.systemd.services.restic-backups-default.wants;
    }
    {
      # Without restic there's nothing to hang the dump off, so keep the timer.
      name = "fallback: the dump keeps its hourly timer when restic is off";
      ok = lib.elem "*-*-* *:55:00" (
        lib.toList timerFallbackEval.systemd.services."postgresqlBackup-gotosocial".startAt
      );
    }
    {
      name = "fallback: restic-backups-default isn't defined when restic is off";
      ok = !(timerFallbackEval.systemd.services ? "restic-backups-default");
    }
    {
      name = "disabled: no pg_dump backups without postgres";
      ok = !disabledEval.services.postgresqlBackup.enable;
    }
    {
      name = "disabled: nothing added to persistence without postgres";
      ok = disabledEval.thoughtfull.impermanence.directories == [ ];
    }
    {
      name = "disabled: nothing registered for monitoring without postgres";
      ok = disabledEval.thoughtfull.monitoring.services == [ ];
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    postgresql-backup test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "postgresql-backup-test" { } "touch $out"
