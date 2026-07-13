{ nixpkgs, self, ... }:
let
  # Apply the thoughtfull overlay so pkgs.thoughtfull.writeFileScriptBin resolves.
  overlayModule = {
    nixpkgs.overlays = [ self.overlays.thoughtfull ];
  };

  imports = [
    ../nixosModules/monitoring.nix
    overlayModule
  ];
in
nixpkgs.testers.nixosTest {
  name = "monitoring";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    machine =
      { pkgs, ... }:
      {
        inherit imports;
        thoughtfull.monitoring = {
          enable = true;
          ntfyServer = "http://127.0.0.1:8000";
          ntfyTopic = "test-topic";
        };
        # Test-only: a mock ntfy server to capture what the module sends,
        # since the test VM has no real network access.
        environment.systemPackages = [ pkgs.python3 ];
        environment.etc."mock-ntfy.py".source = ./monitoring/mock-ntfy.py;
      };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    with subtest("ntfy and ntfy-test are on PATH"):
        machine.succeed("which ntfy")
        machine.succeed("which ntfy-test")

    with subtest("start the mock ntfy server"):
        machine.succeed("systemd-run --unit=mock-ntfy --collect python3 /etc/mock-ntfy.py")
        machine.wait_for_open_port(8000)

    with subtest("ntfy-test with no arguments sends the default test message"):
        machine.succeed("ntfy-test")
        log = machine.succeed("cat /tmp/requests.log")
        print(f"requests log:\n{log}")
        assert "/test-topic" in log, "should post to the configured topic"
        assert "This is only a test" in log, "default message should be sent"
        assert "title=Test message" in log, "should set the title"
        assert "tags=rotating_light" in log, "should tag the message with a red alert light"

    with subtest("ntfy-test with an argument sends that argument"):
        machine.succeed("rm -f /tmp/requests.log")
        machine.succeed("ntfy-test 'custom alert body'")
        log = machine.succeed("cat /tmp/requests.log")
        print(f"requests log:\n{log}")
        assert "custom alert body" in log, "argument should be sent as the message"

    with subtest("alert-on-failure-test.service fails on purpose and triggers alert-on-failure"):
        machine.succeed("rm -f /tmp/requests.log")
        machine.fail("systemctl start alert-on-failure-test.service")
        machine.wait_until_succeeds("test -s /tmp/requests.log")
        log = machine.succeed("cat /tmp/requests.log")
        print(f"requests log:\n{log}")
        assert "alert-on-failure-test" in log, "alert-on-failure should report the failed unit"
  '';
}
