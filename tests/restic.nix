{ nixpkgs, self, ... }:
let
  stubs = import ./stubs.nix;
  resticNode =
    extra:
    { pkgs, ... }:
    {
      imports = [
        ../nixosModules/restic.nix
        # Monitoring must be present so the restic module can register the prune
        # job in thoughtfull.monitoring.services; the overlay makes
        # pkgs.thoughtfull.writeFileScriptBin (used by monitoring) resolve.
        ../nixosModules/monitoring.nix
        stubs.ageSecrets
        { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
      ];
      services.restic.thoughtfull = {
        enable = true;
        environmentFile = pkgs.writeText "fake-restic-environment" "";
        # A path so the default job actually emits a backup command; real hosts
        # get their paths from other modules (for example thoughtfull.impermanence).
        paths = [ "/etc" ];
        passwordFile = pkgs.writeText "fake-restic-password" "fake-password";
        repositoryFile = pkgs.writeText "fake-restic-repository" "/tmp/restic-repo";
      }
      // extra;
      # Enable monitoring so the onFailure wiring the restic module requests is
      # actually applied and observable at runtime.
      thoughtfull.monitoring = {
        enable = true;
        ntfyTopic = "test";
      };
    };
in
nixpkgs.testers.nixosTest {
  name = "restic";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    # A plain host (for example a laptop): backs up hourly and never prunes.
    machine = resticNode { };
    # The designated always-on host: also runs the daily repository-wide prune.
    prunehost = resticNode { prune.enable = true; };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    prunehost.wait_for_unit("multi-user.target")

    with subtest("restic-stop-before-sleep is ordered before sleep.target"):
        before = machine.succeed(
            "systemctl show restic-stop-before-sleep.service --property=Before --value"
        )
        print(f"Before={before}")
        assert "sleep.target" in before, "expected Before= to include sleep.target"

    with subtest("restic-stop-before-sleep is wanted by sleep.target"):
        machine.succeed(
            "test -L /etc/systemd/system/sleep.target.wants/restic-stop-before-sleep.service"
        )

    with subtest("restic-stop-before-sleep stops the restic backup service"):
        exec_start = machine.succeed(
            "systemctl show restic-stop-before-sleep.service --property=ExecStart --value"
        )
        print(f"ExecStart={exec_start}")
        assert "restic-backups-default.service" in exec_start, (
            "expected ExecStart to stop restic-backups-default.service"
        )

    with subtest(
        "the hourly backup is backup-only: prune is decoupled so every host is not "
        "running the expensive repository-wide forget+prune 24x/day against the "
        "shared repo"
    ):
        unit = machine.succeed("systemctl cat restic-backups-default.service")
        print(f"unit:\n{unit}")
        assert "restic backup" in unit, "expected the default job to still run a backup"
        assert "forget" not in unit and "--prune" not in unit, (
            "expected the hourly default job to NOT forget/prune"
        )

    with subtest("a host without prune.enable has no standalone prune job"):
        machine.fail("systemctl cat restic-backups-prune.service")

    with subtest(
        "the prune host runs a prune-only forget+prune job with --max-unused 20% "
        "instead of the default 5%, so it repacks rarely rather than every run"
    ):
        unit = prunehost.succeed("systemctl cat restic-backups-prune.service")
        print(f"unit:\n{unit}")
        assert "forget --prune" in unit, "expected the prune job to run forget --prune"
        assert "--max-unused 20%" in unit, (
            "expected the prune job to include --max-unused 20%"
        )
        assert "restic backup" not in unit, (
            "expected the prune job to be prune-only (no backup command)"
        )

    with subtest(
        "the prune job is wired into failure monitoring, since it is now the "
        "only thing pruning the shared repo and a silent failure would quietly "
        "reintroduce unbounded growth"
    ):
        on_failure = prunehost.succeed(
            "systemctl show restic-backups-prune.service --property=OnFailure --value"
        )
        print(f"OnFailure={on_failure}")
        assert "alert-on-failure@restic-backups-prune.service" in on_failure, (
            "expected restic-backups-prune to trigger the failure alert"
        )

    with subtest("the prune job runs daily, not hourly"):
        calendar = prunehost.succeed(
            "systemctl show restic-backups-prune.timer --property=TimersCalendar --value"
        )
        print(f"TimersCalendar={calendar}")
        assert "00:00:00" in calendar, (
            "expected the prune timer to fire daily at midnight"
        )

    with subtest(
        "restic-stop-before-sleep also stops the prune job on the prune host"
    ):
        exec_start = prunehost.succeed(
            "systemctl show restic-stop-before-sleep.service --property=ExecStart --value"
        )
        print(f"ExecStart={exec_start}")
        assert "restic-backups-prune.service" in exec_start, (
            "expected ExecStart to also stop restic-backups-prune.service when prune is enabled"
        )

    with subtest(
        "restic-backups-default treats exit code 130 (restic's graceful response to being stopped) as success"
    ):
        success_exit_status = machine.succeed(
            "systemctl show restic-backups-default.service --property=SuccessExitStatus --value"
        )
        print(f"SuccessExitStatus={success_exit_status}")
        assert "130" in success_exit_status.split(), (
            "expected SuccessExitStatus to include 130 so restic-stop-before-sleep "
            "stopping the backup mid-run isn't reported as a failure"
        )
  '';
}
