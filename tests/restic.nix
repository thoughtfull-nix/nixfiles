{ nixpkgs, ... }:
let
  stubs = import ./stubs.nix;
in
nixpkgs.testers.nixosTest {
  name = "restic";

  skipTypeCheck = true;
  skipLint = true;

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [
        ../nixosModules/restic.nix
        stubs.ageSecrets
      ];
      services.restic.thoughtfull = {
        enable = true;
        environmentFile = pkgs.writeText "fake-restic-environment" "";
        passwordFile = pkgs.writeText "fake-restic-password" "fake-password";
        repositoryFile = pkgs.writeText "fake-restic-repository" "/tmp/restic-repo";
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

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
