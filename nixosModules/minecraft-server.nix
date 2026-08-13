{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services) minecraft-server;
  inherit (config.services.minecraft-server.thoughtfull) worldExport;
  inherit (config.thoughtfull.impermanence) persistent;
  inherit (config.thoughtfull.impermanence.disko) snapshots;
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    ;
  inherit (lib.types) bool str;
  inherit (pkgs.thoughtfull) replaceVarsString;

  # Paper lays out the overworld/nether/end as level-name, level-name_nether,
  # and level-name_the_end; deriving from serverProperties keeps this in sync
  # if a host ever overrides level-name.
  worldName = minecraft-server.serverProperties.level-name or "world";
  worldDirs = [
    worldName
    "${worldName}_nether"
    "${worldName}_the_end"
  ];

  # thoughtfull.impermanence's disko layout (impermanence/gpt.nix) is a
  # single btrfs filesystem with one subvolume per top-level mountpoint; this
  # module already assumes it's in use for the dataDir bind mount below, and
  # worldExport additionally relies on it specifically being btrfs, to
  # snapshot the persistent subvolume for a consistent copy source instead of
  # rsyncing the live, changing directory.
  persistentDir = "/${persistent.name}";
  # A fixed name (not e.g. mktemp'd) is fine: systemd won't run overlapping
  # instances of this unit, and world-export-snapshot-create.bash removes any
  # stale leftover from an interrupted previous run before creating a fresh
  # one.
  snapshotDir = "${snapshots.mountPoint}/minecraft-world-export";

  worldExportSnapshotCreate = pkgs.writeShellScript "minecraft-world-export-snapshot-create" (
    replaceVarsString ./minecraft-server/world-export-snapshot-create.bash {
      inherit persistentDir snapshotDir;
    }
  );
  worldExportSnapshotDelete = pkgs.writeShellScript "minecraft-world-export-snapshot-delete" (
    replaceVarsString ./minecraft-server/world-export-snapshot-delete.bash { inherit snapshotDir; }
  );
in
{
  config = mkIf minecraft-server.enable {
    services.minecraft-server = {
      declarative = mkDefault true;
      eula = mkDefault true;
      openFirewall = mkDefault true;
      package = mkDefault pkgs.thoughtfull.papermc-26-2;
      serverProperties = {
        difficulty = mkDefault 2;
        gamemode = mkDefault 0;
        max-players = mkDefault 5;
        motd = mkDefault "Survive and thrive!";
        server-port = mkDefault 25565;
        simulation-distance = mkDefault 4;
        view-distance = mkDefault 6;
      };
    };
    thoughtfull.impermanence.directories = [
      {
        directory = minecraft-server.dataDir;
        mode = "0750";
        group = "minecraft";
        user = "minecraft";
        # The live world directories churn on every autosave, which makes
        # backing them up hourly via restic expensive for little benefit.
        # Export them to world.bak instead (see worldExport below) and
        # exclude the live copies from restic; everything else in dataDir
        # (server.properties, plugins, world.bak, ...) is still backed up
        # hourly as usual. world.bak.tmp is also excluded: it's the export's
        # working directory while rsync is copying, so an hourly backup that
        # lands mid-export would otherwise pick up a half-written tree.
        backupExclude = mkIf worldExport.enable (worldDirs ++ [ "world.bak.tmp" ]);
      }
    ];

    systemd.services.minecraft-world-export = mkIf worldExport.enable {
      description = "Export the Minecraft world to world.bak for restic to back up";
      after = [ "minecraft-server.service" ];
      path = [
        pkgs.btrfs-progs
        pkgs.coreutils
        pkgs.rsync
      ];
      script = replaceVarsString ./minecraft-server/world-export-copy.bash {
        inherit (minecraft-server) dataDir;
        inherit snapshotDir;
        worldDirs = toString worldDirs;
      };
      serviceConfig = {
        Type = "oneshot";
        User = "minecraft";
        Group = "minecraft";
        WorkingDirectory = minecraft-server.dataDir;
        # Snapshot the persistent subvolume read-only before copying, so the
        # copy source is a frozen point-in-time view instead of a live,
        # changing directory -- this eliminates the torn-write risk a plain
        # rsync of the live world would have. Needs root for the btrfs
        # subvolume ioctls ("+" ignores this unit's User=/Group= for just
        # this command); the copy step above still runs as the unprivileged
        # minecraft user, reading only the minecraft subtree of the snapshot.
        ExecStartPre = "+${worldExportSnapshotCreate}";
        # Always try to remove the snapshot once the unit stops, regardless
        # of how ExecStartPre/ExecStart exited (systemd runs ExecStopPost
        # even when ExecStartPre itself failed), so a failed run doesn't leak
        # a snapshot. Leading "-" so a failure here doesn't retroactively
        # mark this oneshot as failed.
        ExecStopPost = "-+${worldExportSnapshotDelete}";
      };
    };

    systemd.timers.minecraft-world-export = mkIf worldExport.enable {
      description = "Timer for minecraft-world-export.service";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = mkDefault worldExport.dates;
        Persistent = mkDefault true;
        RandomizedDelaySec = mkDefault "15min";
      };
    };
  };
  options.services.minecraft-server.thoughtfull.worldExport = {
    dates = mkOption {
      default = "daily";
      description = "OnCalendar expression for how often to export the world to world.bak.";
      type = str;
    };
    enable = mkOption {
      default = true;
      description = ''
        Export the world directories to `world.bak` inside dataDir on a
        timer, taken from a read-only btrfs snapshot of the persistent
        subvolume for a consistent copy, and exclude the live world
        directories from restic (via thoughtfull.impermanence's
        `backupExclude`), so restic sees only the less-frequently-changing
        export instead of every hourly autosave.
      '';
      type = bool;
    };
  };
}
