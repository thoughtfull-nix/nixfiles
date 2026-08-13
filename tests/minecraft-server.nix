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
          # pkgs.thoughtfull.replaceVarsString (used to render
          # world-snapshot.bash) only resolves once the overlay is applied.
          { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
          ../nixosModules/minecraft-server.nix
          stubs.impermanence
          stubs.resticThoughtfull
        ];
        services.minecraft-server.enable = true;

        # For the test driver's own `btrfs subvolume show` checks below --
        # separate from the `path` given to minecraft-world-snapshot.service
        # itself, which only puts btrfs on that unit's PATH, not the VM's
        # general shell.
        environment.systemPackages = [ pkgs.btrfs-progs ];

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
        # world-snapshot.bash's `btrfs subvolume snapshot` and its
        # snapshot_dir+dataDir path arithmetic are both genuinely exercised.
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
            assertion = config.services.minecraft-server.thoughtfull.worldExport.maxAgeSeconds == 60 * 60 * 24;
            message = "worldExport.maxAgeSeconds should default to a day";
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
                ]
            ) config.thoughtfull.impermanence.directories;
            message = "the live world directories should be excluded from restic backup";
          }
          {
            assertion =
              config.services.restic.thoughtfull.exclude == [
                "/${config.thoughtfull.impermanence.persistent.name}/.minecraft-world-export-snapshot"
              ];
            message = ''
              the snapshot lives directly under the persistent subvolume
              (outside dataDir, so dataDir's own backupExclude entries don't
              reach it) and needs its own top-level restic exclude, or restic
              would back up a full extra copy of /persistent -- including the
              live world data -- for as long as the snapshot exists
            '';
          }
          {
            assertion = config.systemd.services.minecraft-world-snapshot.serviceConfig.Type == "oneshot";
            message = "the snapshot+mount service should be a oneshot";
          }
          {
            assertion = builtins.elem "minecraft-world-snapshot.service" config.systemd.services.restic-backups-default.wants;
            message = "restic-backups-default should want the world snapshot refreshed before it runs";
          }
          {
            assertion = builtins.elem "minecraft-world-snapshot.service" config.systemd.services.restic-backups-default.after;
            message = "restic-backups-default should be ordered after the world snapshot refresh";
          }
        ];
      };

    disabled =
      { config, ... }:
      {
        imports = [
          ../nixosModules/minecraft-server.nix
          stubs.impermanence
          stubs.resticThoughtfull
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
    marker = "/persistent/.minecraft-world-export-snapshot.created"

    def subvolume_id():
        # A more reliable "was a new snapshot created" signal than scraping
        # the journal: recreating a subvolume at the same path always gets a
        # new numeric ID, and this doesn't depend on journal rotation/vacuum
        # timing the way grepping journalctl output for "Create readonly
        # snapshot" does (that's flaky: --vacuum-time=1s won't have deleted
        # an archive that isn't yet a second old, so an earlier subtest's
        # line can still be matched by a later one).
        output = enabled.succeed(
            "btrfs subvolume show /persistent/.minecraft-world-export-snapshot"
        )
        for line in output.splitlines():
            if "Subvolume ID:" in line:
                return line.split(":")[-1].strip()
        raise AssertionError(f"no Subvolume ID in btrfs subvolume show output:\n{output}")

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

    with subtest("enabled: first run creates world.bak, and the mount survives the oneshot exiting"):
        enabled.succeed(
            "mkdir -p /var/lib/minecraft/world/region /var/lib/minecraft/world_nether/region"
        )
        enabled.succeed("echo region-data > /var/lib/minecraft/world/region/r.0.0.mca")
        enabled.succeed("chown -R minecraft:minecraft /var/lib/minecraft/world*")

        enabled.succeed("systemctl start minecraft-world-snapshot.service")

        # A Type=oneshot with no RemainAfterExit goes back to "inactive" once
        # it completes; checking that here (from a separate command, i.e. a
        # separate process) and then checking the bind mounts below (also
        # separate commands) is what actually proves those mounts are visible
        # in the host mount namespace and outlive the unit that created them
        # -- exactly what restic (itself a later, unrelated process) needs.
        # Sandboxing directives like PrivateMounts would break this silently:
        # the mounts would exist only inside the oneshot's own namespace and
        # vanish the moment it exits.
        state = enabled.succeed(
            "systemctl show -p ActiveState --value minecraft-world-snapshot.service"
        ).strip()
        assert state == "inactive", f"expected the oneshot to have exited, got {state}"

        enabled.succeed("mountpoint -q /var/lib/minecraft/world.bak/world")
        enabled.succeed("mountpoint -q /var/lib/minecraft/world.bak/world_nether")

        exported = enabled.succeed("cat /var/lib/minecraft/world.bak/world/region/r.0.0.mca")
        assert "region-data" in exported
        # the live copy stays on disk too -- it's only excluded from restic
        enabled.succeed("test -f /var/lib/minecraft/world/region/r.0.0.mca")

        # restic backs up /persistent, not /var/lib/minecraft -- dataDir is
        # only a bind mount of /persistent+dataDir. This mount was made
        # *under* that bind mount (at /var/lib/minecraft/world.bak/world),
        # so it's only useful to restic if mount propagation carries it back
        # to the /persistent view too. Check that view directly rather than
        # assume it: this is exactly the kind of thing that fails silently
        # (restic would just back up an empty world.bak) if propagation
        # doesn't work the way the no-sandboxing choice above assumes.
        exported_via_persistent = enabled.succeed(
            "cat /persistent/var/lib/minecraft/world.bak/world/region/r.0.0.mca"
        )
        assert "region-data" in exported_via_persistent

        enabled.succeed(f"test -f {marker}")
        first_created = enabled.succeed(f"cat {marker}").strip()
        first_id = subvolume_id()

    with subtest("enabled: a same-day re-run reuses the snapshot instead of recreating it"):
        enabled.succeed("systemctl start minecraft-world-snapshot.service")

        second_created = enabled.succeed(f"cat {marker}").strip()
        assert second_created == first_created, "expected the marker to be unchanged on a same-day re-run"
        assert subvolume_id() == first_id, "expected the same snapshot subvolume to still be in place"

    with subtest("enabled: a stale marker triggers a fresh snapshot"):
        # Well before any possible "today" threshold.
        enabled.succeed(f"echo 0 > {marker}")
        enabled.succeed("systemctl start minecraft-world-snapshot.service")

        third_created = enabled.succeed(f"cat {marker}").strip()
        assert third_created != "0", "expected the marker to be refreshed once stale"
        third_id = subvolume_id()
        assert third_id != first_id, "expected a new snapshot subvolume once the marker is stale"

        exported = enabled.succeed("cat /var/lib/minecraft/world.bak/world/region/r.0.0.mca")
        assert "region-data" in exported

    with subtest("enabled: recovers from a simulated reboot by remounting, not recreating"):
        fresh_created = enabled.succeed(f"cat {marker}").strip()

        # Simulate what a reboot does to these bind mounts: they simply
        # vanish, while the snapshot itself -- real on-disk btrfs data --
        # doesn't. This is the whole basis for the design being reboot-safe
        # without any declarative mount or boot-time logic.
        enabled.succeed("umount /var/lib/minecraft/world.bak/world")
        enabled.succeed("umount /var/lib/minecraft/world.bak/world_nether")
        enabled.fail("mountpoint -q /var/lib/minecraft/world.bak/world")

        enabled.succeed("systemctl start minecraft-world-snapshot.service")

        recovered_created = enabled.succeed(f"cat {marker}").strip()
        assert recovered_created == fresh_created, (
            "expected recovery to remount the existing snapshot, not create a new one"
        )
        assert subvolume_id() == third_id, (
            "expected recovery to reuse the existing snapshot subvolume, not create a new one"
        )

        enabled.succeed("mountpoint -q /var/lib/minecraft/world.bak/world")
        exported = enabled.succeed("cat /var/lib/minecraft/world.bak/world/region/r.0.0.mca")
        assert "region-data" in exported
  '';
}
