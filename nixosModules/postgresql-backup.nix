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
        enable = mkDefault config.services.postgresql.enable;
        startAt = mkDefault "*-*-* *:55:00";
      };
    }
    (mkIf cfg.enable {
      thoughtfull.impermanence.directories = [
        {
          directory = cfg.location;
          user = "postgres";
          group = "postgres";
          mode = "0700";
        }
      ];
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
