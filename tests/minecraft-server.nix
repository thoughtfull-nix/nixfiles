{ self, nixpkgs, ... }:
let
  stubs = import ./stubs.nix;
in
nixpkgs.testers.nixosTest {
  name = "minecraft-server";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    enabled =
      {
        config,
        pkgs,
        ...
      }:
      {
        imports = [
          # pkgs.thoughtfull.replaceVarsString (used to render the
          # world-export scripts) only resolves once the overlay is applied.
          { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
          ../nixosModules/minecraft-server.nix
          stubs.impermanence
        ];
        services.minecraft-server.enable = true;

        # Swap the real PaperMC jar for a harmless fake so the test doesn't
        # need internet access to let Paperclip download the vanilla server
        # jar it wraps.
        services.minecraft-server.package = pkgs.writeShellScriptBin "minecraft-server" ''
          echo "fake minecraft server started"
          exec cat
        '';

        # worldExport's whole point is to snapshot a real btrfs subvolume, so
        # faking `btrfs` would validate nothing about the feature. Instead,
        # set up a small loopback btrfs filesystem and bind-mount dataDir
        # onto it -- the same relationship thoughtfull.impermanence's real
        # bind mount gives dataDir in production -- so
        # world-export-snapshot-create.bash's `btrfs subvolume snapshot` and
        # world-export-copy.bash's snapshot_dir+dataDir path arithmetic are
        # both genuinely exercised. The snapshot destination is nested inside
        # /persistent itself (valid btrfs usage) rather than standing up a
        # second mountpoint just for the test; production keeps the real,
        # separate /snapshots subvolume (see minecraft-server.nix).
        thoughtfull.impermanence.disko.snapshots.mountPoint = "/persistent/.snapshots";
        systemd.services.setup-test-persistent = {
          wantedBy = [ "multi-user.target" ];
          before = [ "minecraft-server.service" ];
          path = [
            pkgs.btrfs-progs
            pkgs.coreutils
            pkgs.util-linux
          ];
          serviceConfig.Type = "oneshot";
          script = ''
            mkdir -p /persistent
            truncate -s 512M /btrfs-test.img
            mkfs.btrfs -q /btrfs-test.img
            mount -o loop /btrfs-test.img /persistent

            mkdir -p /persistent/var/lib/minecraft
            chown minecraft:minecraft /persistent/var/lib/minecraft
            chmod 0750 /persistent/var/lib/minecraft
            mkdir -p /var/lib/minecraft
            mount --bind /persistent/var/lib/minecraft /var/lib/minecraft
          '';
        };

        assertions = [
          {
            assertion = config.services.minecraft-server.eula;
            message = "eula should default to true";
          }
          {
            assertion = config.services.minecraft-server.declarative;
            message = "declarative should default to true so serverProperties take effect";
          }
          {
            assertion = config.services.minecraft-server.openFirewall;
            message = "openFirewall should default to true";
          }
          {
            assertion = builtins.elem 25565 config.networking.firewall.allowedTCPPorts;
            message = "the default server port should be opened in the firewall";
          }
          {
            assertion = builtins.any (
              d: (d.directory or null) == config.services.minecraft-server.dataDir
            ) config.thoughtfull.impermanence.directories;
            message = "expected minecraft-server dataDir persistence directory";
          }
          {
            assertion = config.services.minecraft-server.thoughtfull.worldExport.enable;
            message = "worldExport should default to enabled";
          }
          {
            assertion = builtins.any (
              d:
              (d.directory or null) == config.services.minecraft-server.dataDir
              &&
                (d.backupExclude or [ ]) == [
                  "world"
                  "world_nether"
                  "world_the_end"
                  "world.bak.tmp"
                ]
            ) config.thoughtfull.impermanence.directories;
            message = "the live world directories and export tmp dir should be excluded from restic backup";
          }
          {
            assertion = config.systemd.timers.minecraft-world-export.timerConfig.OnCalendar == "daily";
            message = "the world export timer should default to running daily";
          }
          {
            assertion = config.systemd.services.minecraft-world-export.serviceConfig.ExecStartPre != null;
            message = "a root-privileged ExecStartPre should create the read-only snapshot";
          }
          {
            assertion = config.systemd.services.minecraft-world-export.serviceConfig.ExecStopPost != null;
            message = "a root-privileged ExecStopPost should always clean up the snapshot";
          }
        ];
      };

    disabled =
      { config, ... }:
      {
        imports = [
          ../nixosModules/minecraft-server.nix
          stubs.impermanence
        ];

        assertions = [
          {
            assertion = !config.services.minecraft-server.enable;
            message = "minecraft-server should stay disabled by default";
          }
          {
            assertion = config.thoughtfull.impermanence.directories == [ ];
            message = "no persistence directory should be added when disabled";
          }
        ];
      };
  };

  testScript = ''
    start_all()
    enabled.wait_for_unit("multi-user.target")
    disabled.wait_for_unit("multi-user.target")

    with subtest("enabled: minecraft-server.service reaches active"):
        enabled.wait_for_unit("minecraft-server.service")
        enabled.succeed("systemctl is-active --quiet minecraft-server.service")

    with subtest("enabled: eula is accepted on disk"):
        eula = enabled.succeed("cat /var/lib/minecraft/eula.txt")
        print(f"eula.txt:\n{eula}")
        assert "eula=true" in eula

    with subtest("enabled: default server properties are rendered declaratively"):
        properties = enabled.succeed("cat /var/lib/minecraft/server.properties")
        print(f"server.properties:\n{properties}")
        assert "difficulty=2" in properties
        assert "gamemode=0" in properties
        assert "max-players=5" in properties
        assert "server-port=25565" in properties

    with subtest("disabled: minecraft-server.service is not present"):
        disabled.fail("systemctl status minecraft-server.service")

    with subtest("enabled: dataDir is really backed by the loopback btrfs filesystem"):
        enabled.succeed("mountpoint -q /persistent")
        mounts = enabled.succeed("cat /proc/self/mountinfo")
        assert " /var/lib/minecraft " in mounts

    with subtest("enabled: world export snapshots a real btrfs subvolume and copies from it"):
        enabled.succeed(
            "mkdir -p /var/lib/minecraft/world/region /var/lib/minecraft/world_nether/region"
        )
        enabled.succeed("echo region-data > /var/lib/minecraft/world/region/r.0.0.mca")
        enabled.succeed("chown -R minecraft:minecraft /var/lib/minecraft/world*")

        # systemctl start blocks until a oneshot unit (and its
        # ExecStartPre/ExecStopPost) finishes, so the export has fully
        # completed, snapshot included, by the time this returns.
        enabled.succeed("systemctl start minecraft-world-export.service")

        exported = enabled.succeed("cat /var/lib/minecraft/world.bak/world/region/r.0.0.mca")
        assert "region-data" in exported
        enabled.succeed("test -d /var/lib/minecraft/world.bak/world_nether")
        enabled.fail("test -e /var/lib/minecraft/world.bak.tmp")
        # the live copy stays on disk -- it's only excluded from restic, not deleted
        enabled.succeed("test -f /var/lib/minecraft/world/region/r.0.0.mca")
        # ExecStopPost should have removed the snapshot once the copy was done
        enabled.fail("test -e /persistent/.snapshots/minecraft-world-export")

    with subtest("enabled: a second export run doesn't fail or leak a snapshot"):
        enabled.succeed("systemctl start minecraft-world-export.service")
        enabled.fail("test -e /persistent/.snapshots/minecraft-world-export")

    with subtest("enabled: an unreadable snapshot fails loudly instead of shipping an empty world.bak"):
        # Simulate a parent directory inside the snapshot missing the
        # traversal bit for the minecraft user (e.g. a real host where
        # /persistent's layout doesn't grant it), by revoking "other" access
        # to /persistent/var. This doesn't affect the live server: it reaches
        # /var/lib/minecraft directly through the bind mount, not by
        # traversing /persistent/var.
        enabled.succeed("chmod 0700 /persistent/var")
        enabled.fail("systemctl start minecraft-world-export.service")
        # ExecStopPost must still have cleaned up the snapshot even though
        # the copy step failed.
        enabled.fail("test -e /persistent/.snapshots/minecraft-world-export")
        # world.bak from the last successful run is untouched, not clobbered
        # with an empty one.
        untouched = enabled.succeed("cat /var/lib/minecraft/world.bak/world/region/r.0.0.mca")
        assert "region-data" in untouched

        enabled.succeed("chmod 0755 /persistent/var")
        enabled.succeed("systemctl start minecraft-world-export.service")
  '';
}
