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
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    ;
  inherit (lib.types) bool int;
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
  # reading the live, changing directory.
  persistentDir = "/${persistent.name}";
  # Nested inside the persistent subvolume itself (valid btrfs usage --
  # snapshotting a subvolume into a directory within itself), rather than the
  # dedicated thoughtfull.impermanence.disko.snapshots subvolume: that one is
  # mounted read-only by default (it holds long-lived root-rollback history,
  # not meant to be written to at runtime), which would make `btrfs subvolume
  # snapshot` fail with EROFS here. persistentDir is always writable, since
  # live application data (including dataDir) already lives there.
  snapshotDir = "${persistentDir}/.minecraft-world-export-snapshot";
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
        # world.bak (bind-mounted from a periodically-refreshed read-only
        # btrfs snapshot, see worldExport below) is what restic actually
        # backs up instead; exclude the live copies here so restic doesn't
        # see them directly. Everything else in dataDir (server.properties,
        # plugins, world.bak, ...) is still backed up hourly as usual.
        backupExclude = mkIf worldExport.enable worldDirs;
      }
    ];
    # The transient snapshot sits directly under persistentDir (outside
    # dataDir), so the backupExclude entries above don't reach it. It's a
    # full read-only clone of the persistent subvolume -- including the live
    # world data this feature exists to keep out of restic -- for as long as
    # it exists (up to a day), so it needs its own top-level exclude.
    services.restic.thoughtfull.exclude = mkIf worldExport.enable [ snapshotDir ];

    # Runs immediately before every restic backup (see the wants/after wired
    # into restic-backups-default below) rather than on its own timer: keeps
    # world.bak's snapshot refresh (once maxAgeSeconds has elapsed) and
    # restic's read of it from ever racing each other, and doubles as
    # self-healing after a reboot -- the snapshot itself is real on-disk data
    # and survives one, only the bind mounts below don't, so the very next
    # restic run just remounts it without needing to recreate anything.
    #
    # Deliberately no sandboxing (no PrivateTmp/ProtectSystem/PrivateMounts/
    # etc.): those directives put the unit in its own mount namespace, which
    # would make the bind mounts below invisible to restic (a separate,
    # later process) the moment this oneshot exits.
    systemd.services.minecraft-world-snapshot = mkIf worldExport.enable {
      description = "Snapshot the Minecraft world and bind-mount it at world.bak for restic";
      path = [
        pkgs.btrfs-progs
        pkgs.coreutils
        pkgs.util-linux
      ];
      script = replaceVarsString ./minecraft-server/world-snapshot.bash {
        inherit (minecraft-server) dataDir;
        inherit persistentDir snapshotDir;
        maxAgeSeconds = toString worldExport.maxAgeSeconds;
        worldDirs = toString worldDirs;
      };
      serviceConfig.Type = "oneshot";
    };
    # Added on the consuming side (rather than worldExport reaching in with
    # wantedBy/before) so the dependency direction is unambiguous: restic
    # wants the snapshot fresh before it runs, not the other way around.
    # Wants rather than Requires: a btrfs hiccup here should only risk
    # world.bak being stale or briefly missing for that hour, not block the
    # rest of the system (home directory, ssh keys, everything else) from
    # being backed up too.
    systemd.services.restic-backups-default = mkIf worldExport.enable {
      wants = [ "minecraft-world-snapshot.service" ];
      after = [ "minecraft-world-snapshot.service" ];
    };
  };
  options.services.minecraft-server.thoughtfull.worldExport = {
    enable = mkOption {
      default = true;
      description = ''
        Snapshot the world directories (via a read-only btrfs snapshot of the
        persistent subvolume) and bind-mount them at `world.bak` inside
        dataDir immediately before every restic backup, refreshing the
        snapshot once it's older than `maxAgeSeconds`. Excludes the live
        world directories from restic (via thoughtfull.impermanence's
        `backupExclude`), so restic sees only the less-frequently-refreshed
        snapshot instead of every hourly autosave.
      '';
      type = bool;
    };
    maxAgeSeconds = mkOption {
      default = 60 * 60 * 24;
      description = ''
        How old (in seconds) the world snapshot is allowed to get before it's
        refreshed. btrfs snapshots are effectively instantaneous and don't
        disrupt the running server, so this is just about how much churn
        restic sees, not about timing around player activity.
      '';
      type = int;
    };
  };
}
