{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    genAttrs
    map
    mkDefault
    mkForce
    mkIf
    mkMerge
    ;
  cfg = config.services.postgresqlBackup;
  resticEnabled = config.services.restic.thoughtfull.enable;
  # The dump unit(s) upstream generates: a single pg_dumpall unit for the whole
  # cluster when no databases are named, else one per named database.
  dumpUnits =
    if cfg.backupAll then [ "postgresqlBackup" ] else map (db: "postgresqlBackup-${db}") cfg.databases;
in
{
  config = mkMerge [
    {
      services.postgresqlBackup = {
        # Back up wherever PostgreSQL runs.
        enable = mkDefault config.services.postgresql.enable;
        # Fallback schedule, used only on hosts where restic isn't managing the
        # timing (see the restic block below); there the timer is disabled and
        # the dump runs immediately before the backup instead.
        startAt = mkDefault "*-*-* *:55:00";
      };
    }
    (mkIf cfg.enable {
      # The pg_dump output is the crash-consistent database backup, so it must
      # be in the restic set. Persisting it via impermanence puts it under
      # /persistent, which is exactly what restic backs up. (The live postgres
      # data directory is persisted-but-excluded elsewhere, since file-copying a
      # running datadir isn't consistent.) Owned by postgres to match the dir
      # the upstream module's tmpfiles rule creates.
      thoughtfull.impermanence.directories = [
        {
          directory = cfg.location;
          user = "postgres";
          group = "postgres";
          mode = "0700";
        }
      ];
      # A silently failing dump would leave restic backing up an ever-staler
      # copy, so alert on the dump unit(s).
      thoughtfull.monitoring.services = dumpUnits;
    })
    (mkIf (cfg.enable && resticEnabled) {
      # Run the dump as a dependency of the restic backup rather than on its own
      # timer, so restic always captures a just-made dump instead of relying on
      # two independent schedules happening to line up. Disable the standalone
      # timer(s), and have restic want + order after the dump unit(s). `wants`
      # (not `requires`) so a failed dump still lets restic back up the previous
      # dump rather than skipping the whole backup -- monitoring alerts on the
      # failure separately.
      systemd.services =
        (genAttrs dumpUnits (_: {
          startAt = mkForce [ ];
        }))
        // {
          restic-backups-default = {
            wants = map (u: "${u}.service") dumpUnits;
            after = map (u: "${u}.service") dumpUnits;
          };
        };
    })
  ];
}
