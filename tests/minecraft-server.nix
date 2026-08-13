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
        # set up a small loopback btrfs filesystem with a persistent and a
        # snapshots subvolume, both mounted from a /dev/mapper/encrypted
        # device -- mirroring thoughtfull.impermanence's real disko layout
        # (a LUKS-mapped device backing both) closely enough to exercise it
        # genuinely: persistent mounted read-write with dataDir bind-mounted
        # out of it, snapshots mounted read-only, and the same device path
        # world-snapshot.bash privately mounts to refresh its snapshot. So
        # its `btrfs subvolume snapshot`, its private read-write mount, and
        # its path arithmetic are all genuinely exercised.
        systemd.services.setup-test-persistent = {
          wantedBy = [ "multi-user.target" ];
          before = [ "minecraft-server.service" ];
          path = [
            pkgs.btrfs-progs
            pkgs.coreutils
            pkgs.lvm2 # dmsetup
            pkgs.util-linux
          ];
          serviceConfig.Type = "oneshot";
          script = ''
            truncate -s 512M /btrfs-test.img
            loop=$(losetup --show -f /btrfs-test.img)

            mkfs.btrfs -q "$loop"
            mkdir -p /mnt-btrfs-test-init
            mount "$loop" /mnt-btrfs-test-init
            btrfs subvolume create /mnt-btrfs-test-init/persistent
            btrfs subvolume create /mnt-btrfs-test-init/snapshots
            umount /mnt-btrfs-test-init

            sectors=$(blockdev --getsz "$loop")
            dmsetup create encrypted --table "0 $sectors linear $loop 0"

            mkdir -p /persistent /snapshots
            mount -o subvol=/persistent /dev/mapper/encrypted /persistent
            mount -o subvol=/snapshots,ro /dev/mapper/encrypted /snapshots

            mkdir -p /persistent/var/lib/minecraft
            chown minecraft:minecraft /persistent/var/lib/minecraft
            chmod 0750 /persistent/var/lib/minecraft
            mkdir -p /var/lib/minecraft
            mount --bind /persistent/var/lib/minecraft /var/lib/minecraft
          '';
        };

        # minecraft-server.nix only adds wants/after to restic-backups-default
        # (the real restic module isn't imported here -- it needs age.secrets
        # for real encrypted repository credentials). This stub gives it an
        # actual, startable script merged in alongside that wants/after, so
        # the "doesn't block restic" subtest below can genuinely start it
        # rather than just inspect the unit definition.
        systemd.services.restic-backups-default = {
          description = "stub restic-backups-default for testing wants/after in isolation";
          serviceConfig.Type = "oneshot";
          script = "true";
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
          {
            assertion = builtins.elem "alert-on-failure@%n.service" config.systemd.services.minecraft-world-snapshot.onFailure;
            message = "a failed refresh should trigger a notification";
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
    # Kept in dataDir rather than next to the snapshot: the snapshot can
    # legitimately disappear on its own (see the pruning subtest below), so
    # the marker needs to survive that independently.
    marker = "/var/lib/minecraft/.last-world-snapshot"
    snapshot_dir = "/snapshots/.minecraft-world-export-snapshot"

    def subvolume_id():
        # A more reliable "was a new snapshot created" signal than scraping
        # the journal: recreating a subvolume at the same path always gets a
        # new numeric ID, and this doesn't depend on journal rotation/vacuum
        # timing the way grepping journalctl output for "Create readonly
        # snapshot" does (that's flaky: --vacuum-time=1s won't have deleted
        # an archive that isn't yet a second old, so an earlier subtest's
        # line can still be matched by a later one).
        output = enabled.succeed(f"btrfs subvolume show {snapshot_dir}")
        for line in output.splitlines():
            if "Subvolume ID:" in line:
                return line.split(":")[-1].strip()
        raise AssertionError(f"no Subvolume ID in btrfs subvolume show output:\n{output}")

    def start_and_get_log(unit="minecraft-world-snapshot.service", expect_fail=False):
        # Scoped to just this invocation's lines rather than grepping the
        # whole unit history, so (unlike the journal-scraping subvolume_id()
        # used to do) it isn't sensitive to earlier subtests' log lines still
        # being around. A line count rather than --since timestamp: this
        # test runs fast enough that consecutive invocations can land in the
        # same wall-clock second, which --since's 1-second resolution can't
        # tell apart.
        before = int(enabled.succeed(f"journalctl -u {unit} --no-pager -q | wc -l").strip())
        if expect_fail:
            enabled.fail(f"systemctl start {unit}")
        else:
            enabled.succeed(f"systemctl start {unit}")
        return enabled.succeed(f"journalctl -u {unit} --no-pager -q | tail -n +{before + 1}")

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
        enabled.succeed("mountpoint -q /snapshots")
        mounts = enabled.succeed("cat /proc/self/mountinfo")
        assert " /var/lib/minecraft " in mounts

    with subtest("enabled: /snapshots is read-only until a refresh needs it"):
        enabled.fail("touch /snapshots/should-fail")

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

        # /snapshots itself is never remounted rw -- the refresh above went
        # through a private mount of the same subvolume instead -- so it
        # should still be exactly as read-only as it started.
        enabled.fail("touch /snapshots/should-fail")

        # world.bak itself (not the world subdirectories bind-mounted into
        # it, whose ownership/mode come from whatever's mounted there)
        # should be minecraft:minecraft 0700, not root:root 0755 from a bare
        # mkdir -p.
        owner = enabled.succeed(
            "stat -c '%U:%G %a' /var/lib/minecraft/world.bak"
        ).strip()
        assert owner == "minecraft:minecraft 700", f"expected minecraft:minecraft 700, got {owner}"

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
        log = start_and_get_log()
        # The step-by-step logging should make clear which side of the
        # refresh-or-not branch actually ran, not just what the end result
        # was.
        assert "still-fresh branch" in log, f"expected the still-fresh branch to be logged:\n{log}"
        assert "rebuild branch" not in log, f"did not expect the rebuild branch to be logged:\n{log}"

        second_created = enabled.succeed(f"cat {marker}").strip()
        assert second_created == first_created, "expected the marker to be unchanged on a same-day re-run"
        assert subvolume_id() == first_id, "expected the same snapshot subvolume to still be in place"

    with subtest("enabled: a stale marker triggers a fresh snapshot"):
        # Well before any possible "today" threshold.
        enabled.succeed(f"echo 0 > {marker}")
        log = start_and_get_log()
        assert "rebuild branch" in log, f"expected the rebuild branch to be logged:\n{log}"
        assert "still-fresh branch" not in log, f"did not expect the still-fresh branch to be logged:\n{log}"

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

    with subtest("enabled: a snapshot missing for any other reason still triggers a rebuild"):
        # The marker alone isn't enough to skip a refresh -- snapshot_dir
        # itself has to exist too. Exercise that directly by deleting the
        # subvolume out from under a still-fresh marker (an interrupted
        # refresh or a manual delete could do this; thoughtfull.
        # impermanence's own boot-time rollback prune can't, since its glob
        # skips this snapshot's leading dot). Deleted via a private mount of
        # the same device, the same way world-snapshot.bash itself refreshes
        # it -- /snapshots stays read-only throughout, exactly as in
        # production.
        enabled.succeed("umount /var/lib/minecraft/world.bak/world")
        enabled.succeed("umount /var/lib/minecraft/world.bak/world_nether")

        pre_delete_created = enabled.succeed(f"cat {marker}").strip()

        enabled.succeed("mkdir -p /run/simulate-missing-snapshot")
        enabled.succeed(
            "mount -o subvol=/snapshots /dev/mapper/encrypted /run/simulate-missing-snapshot"
        )
        enabled.succeed(
            "btrfs subvolume delete /run/simulate-missing-snapshot/.minecraft-world-export-snapshot"
        )
        enabled.succeed("umount /run/simulate-missing-snapshot")

        enabled.succeed("systemctl start minecraft-world-snapshot.service")

        post_delete_created = enabled.succeed(f"cat {marker}").strip()
        assert post_delete_created != pre_delete_created, (
            "a fresh marker alone doesn't guarantee a valid snapshot -- it "
            "needs to be rebuilt once the snapshot it points at is gone"
        )

        enabled.succeed("mountpoint -q /var/lib/minecraft/world.bak/world")
        exported = enabled.succeed("cat /var/lib/minecraft/world.bak/world/region/r.0.0.mca")
        assert "region-data" in exported

    with subtest("enabled: a refresh that fails partway degrades to stale, not empty"):
        # Deterministically fail the snapshot creation step: pre-create the
        # temp path world-snapshot.bash builds the replacement under as a
        # plain file instead of a subvolume, so its own "clear any leftover
        # from an interrupted attempt" delete errors out immediately -- well
        # before world.bak is ever touched. This stands in for the real
        # failure modes that step is actually exposed to (ENOSPC, a
        # transient btrfs error, the old subvolume being busy).
        enabled.succeed("mkdir -p /run/inject-fault")
        enabled.succeed("mount -o subvol=/snapshots /dev/mapper/encrypted /run/inject-fault")
        enabled.succeed("touch /run/inject-fault/.minecraft-world-export-snapshot.new")
        enabled.succeed("umount /run/inject-fault")

        enabled.succeed(f"echo 0 > {marker}")
        pre_fail_id = subvolume_id()

        log = start_and_get_log(expect_fail=True)

        # onFailure is set on the unit, so a failure like this one should
        # always trigger an attempt to alert -- systemd logs this even
        # though alert-on-failure@ itself isn't defined here (this test
        # doesn't import thoughtfull.monitoring), since that's a harmless
        # no-op rather than a hard failure (verified separately).
        assert "OnFailure=" in log, f"expected an OnFailure= trigger to be logged:\n{log}"

        # world.bak was never unmounted, so it's still serving the previous,
        # still-valid snapshot -- stale, but not empty.
        enabled.succeed("mountpoint -q /var/lib/minecraft/world.bak/world")
        exported = enabled.succeed("cat /var/lib/minecraft/world.bak/world/region/r.0.0.mca")
        assert "region-data" in exported
        assert subvolume_id() == pre_fail_id, "the old snapshot should be untouched by the failed refresh"

        # And the marker was never rewritten either, so the next run knows
        # a refresh is still due rather than believing the failed attempt
        # succeeded.
        assert enabled.succeed(f"cat {marker}").strip() == "0"

        # Clearing the injected fault and retrying recovers normally.
        enabled.succeed("mkdir -p /run/clear-fault")
        enabled.succeed("mount -o subvol=/snapshots /dev/mapper/encrypted /run/clear-fault")
        enabled.succeed("rm /run/clear-fault/.minecraft-world-export-snapshot.new")
        enabled.succeed("umount /run/clear-fault")

        enabled.succeed("systemctl start minecraft-world-snapshot.service")

        assert enabled.succeed(f"cat {marker}").strip() != "0"
        assert subvolume_id() != pre_fail_id
        exported = enabled.succeed("cat /var/lib/minecraft/world.bak/world/region/r.0.0.mca")
        assert "region-data" in exported

    with subtest("enabled: a failed refresh doesn't stop the restic backup"):
        # Reuses the same fault-injection technique as above to make
        # minecraft-world-snapshot fail deterministically, then starts
        # restic-backups-default directly (which pulls in
        # minecraft-world-snapshot per wants/after as part of that job) to
        # prove -- at the systemd level, not just by inspecting the unit
        # definition -- that Wants/After really does mean a failure here
        # doesn't block the backup.
        enabled.succeed("mkdir -p /run/inject-fault-2")
        enabled.succeed("mount -o subvol=/snapshots /dev/mapper/encrypted /run/inject-fault-2")
        enabled.succeed("touch /run/inject-fault-2/.minecraft-world-export-snapshot.new")
        enabled.succeed("umount /run/inject-fault-2")
        enabled.succeed(f"echo 0 > {marker}")

        enabled.succeed("systemctl start restic-backups-default.service")

        assert (
            enabled.succeed(
                "systemctl show -p ActiveState --value minecraft-world-snapshot.service"
            ).strip()
            == "failed"
        ), "expected the dependency to have genuinely failed, not been skipped"
        assert (
            enabled.succeed(
                "systemctl show -p Result --value restic-backups-default.service"
            ).strip()
            == "success"
        ), "expected restic-backups-default to succeed despite its wants/after dependency failing"

        # Clean up the fault so nothing here leaks into a hypothetical later
        # subtest.
        enabled.succeed("mkdir -p /run/clear-fault-2")
        enabled.succeed("mount -o subvol=/snapshots /dev/mapper/encrypted /run/clear-fault-2")
        enabled.succeed("rm /run/clear-fault-2/.minecraft-world-export-snapshot.new")
        enabled.succeed("umount /run/clear-fault-2")
  '';
}
