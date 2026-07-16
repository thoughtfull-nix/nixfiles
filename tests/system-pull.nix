{ nixpkgs, self, ... }:
let
  # Apply the thoughtfull overlay so pkgs.thoughtfull.system-pull resolves.
  overlayModule = {
    nixpkgs.overlays = [ self.overlays.thoughtfull ];
  };

  # Stub the agenix `age.secrets` option so we can test the module's
  # systemd wiring without actually pulling in the agenix activation scripts
  # (which need a real SSH identity to decrypt).
  ageSecretsStub =
    { lib, ... }:
    {
      options.age.secrets = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                file = lib.mkOption { type = lib.types.path; };
                mode = lib.mkOption {
                  type = lib.types.str;
                  default = "0400";
                };
                path = lib.mkOption {
                  type = lib.types.str;
                  default = "/run/agenix/${name}";
                };
              };
            }
          )
        );
      };
    };

  # Stub thoughtfull.graphical.enable so the module's `dates` default can
  # branch on it without pulling in nixosModules/graphical.nix.
  graphicalStub =
    { lib, ... }:
    {
      options.thoughtfull.graphical.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };

  imports = [
    ../nixosModules/binary-cache.nix
    ../nixosModules/system-pull.nix
    ageSecretsStub
    graphicalStub
    overlayModule
  ];
in
nixpkgs.testers.nixosTest {
  name = "system-pull";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    # Credentials configured, default `enable` propagates to true.
    headless =
      { pkgs, ... }:
      {
        inherit imports;
        thoughtfull.binaryCache.awsCredentialsFile = pkgs.writeText "fake-creds" "AWS_ACCESS_KEY_ID=x\nAWS_SECRET_ACCESS_KEY=y\n";
      };

    graphical =
      { pkgs, ... }:
      {
        inherit imports;
        thoughtfull.graphical.enable = true;
        thoughtfull.binaryCache.awsCredentialsFile = pkgs.writeText "fake-creds" "AWS_ACCESS_KEY_ID=x\nAWS_SECRET_ACCESS_KEY=y\n";
      };

    # No credentials => systemPull default is false, no timer/service.
    noCredentials = {
      inherit imports;
      thoughtfull.binaryCache.awsCredentialsFile = null;
    };
  };

  testScript = ''
    start_all()
    headless.wait_for_unit("multi-user.target")
    graphical.wait_for_unit("multi-user.target")
    noCredentials.wait_for_unit("multi-user.target")

    with subtest("headless default: timer fires at 3am"):
        timer = headless.succeed("systemctl cat system-pull.timer")
        print(f"headless timer:\n{timer}")
        assert "OnCalendar=*-*-* 03:00:00" in timer, (
            "headless host should fire at 3am"
        )
        assert "RandomizedDelaySec=15min" in timer, (
            "should have 15min randomized delay"
        )
        assert "Persistent=true" in timer, (
            "timer should be Persistent so missed runs catch up"
        )

    with subtest("graphical default: timer fires at noon"):
        timer = graphical.succeed("systemctl cat system-pull.timer")
        print(f"graphical timer:\n{timer}")
        assert "OnCalendar=*-*-* 12:00:00" in timer, (
            "graphical host should fire at noon"
        )

    with subtest("service invokes system-pull with no arguments and keeps creds out of its environment"):
        unit = headless.succeed("systemctl cat system-pull.service")
        print(f"headless service:\n{unit}")
        assert "EnvironmentFile=" not in unit, (
            "AWS credentials must not be loaded into system-pull.service's "
            "environment: they would leak into switch-to-configuration and the "
            "activation scripts it runs. The script loads them scoped to the "
            "pointer fetch instead."
        )
        exec_line = next(
            line for line in unit.splitlines() if line.startswith("ExecStart=")
        )
        assert exec_line == "ExecStart=/run/current-system/sw/bin/system-pull", (
            "ExecStart should invoke system-pull with no arguments (bucket, "
            f"region, and creds path are baked in); got:\n{exec_line}"
        )
        assert "/nix/store/" not in exec_line, (
            "ExecStart must not embed a store path, or activation would "
            "stop system-pull.service mid-switch"
        )

    with subtest("service opts out of stop-on-removal so an in-flight switch survives"):
        # If a pulled generation removes system-pull.service, activation would
        # otherwise SIGTERM it (X-StopOnRemoval defaults true) and kill the
        # in-process switch. X-StopOnRemoval=false keeps the running instance
        # alive until the switch it is running finishes.
        unit = headless.succeed("systemctl cat system-pull.service")
        assert "X-StopOnRemoval=false" in unit, (
            "service must set X-StopOnRemoval=false so activation cannot stop "
            "it mid-switch when a pulled generation removes the unit"
        )

    with subtest("switch-to-configuration runs in-process, not via systemd-run"):
        # The stable ExecStart keeps system-pull.service byte-identical across
        # generations, so activation leaves it untouched. The switch can then
        # run in-process and its output lands in system-pull.service's journal.
        exec_start = headless.succeed(
            "systemctl show system-pull.service -p ExecStart --value"
        )
        script_path = exec_start.split("argv[]=")[1].split()[0]
        script = headless.succeed(f"cat {script_path}")
        print(f"system-pull script:\n{script}")
        # Strip comment lines so the check isn't fooled by prose.
        code = "\n".join(
            line for line in script.splitlines() if not line.lstrip().startswith("#")
        )
        assert "switch-to-configuration" in code, (
            "system-pull must invoke switch-to-configuration"
        )
        assert "systemd-run" not in code, (
            "system-pull must invoke switch-to-configuration in-process; the "
            "stable ExecStart means activation won't kill it, so the "
            "systemd-run transient-unit wrapper is no longer needed"
        )

    with subtest("credentials are loaded scoped via dotenvy, not sourced"):
        # AWS creds are only needed for the pointer fetch, so load them into the
        # environment of just that command with dotenvy (which parses the file
        # rather than executing it) instead of sourcing the file or exporting
        # the creds process-wide via EnvironmentFile.
        exec_start = headless.succeed(
            "systemctl show system-pull.service -p ExecStart --value"
        )
        script_path = exec_start.split("argv[]=")[1].split()[0]
        script = headless.succeed(f"cat {script_path}")
        code = "\n".join(
            line for line in script.splitlines() if not line.lstrip().startswith("#")
        )
        assert "dotenvy -f" in code, (
            "system-pull must load AWS credentials with 'dotenvy -f <file>' "
            "scoped to the command that needs them"
        )
        assert "source " not in code, (
            "system-pull must not source the credentials file"
        )

    with subtest("bucket, region, and credentials path are baked into the script"):
        exec_start = headless.succeed(
            "systemctl show system-pull.service -p ExecStart --value"
        )
        script_path = exec_start.split("argv[]=")[1].split()[0]
        script = headless.succeed(f"cat {script_path}")
        assert 'bucket="thoughtfull-nix-cache"' in script, (
            f"bucket should be baked in; got:\n{script}"
        )
        assert 'region="us-east-1"' in script, (
            f"region should be baked in; got:\n{script}"
        )
        assert 'creds_file="/run/agenix/nix-cache-credentials"' in script, (
            f"credentials path should be baked in; got:\n{script}"
        )

    with subtest("nix.conf gets s3:// substituter and trusted public key"):
        nix_conf = headless.succeed("cat /etc/nix/nix.conf")
        print(f"headless nix.conf:\n{nix_conf}")
        assert "s3://thoughtfull-nix-cache?region=us-east-1" in nix_conf, (
            "nix.conf should include the s3 substituter"
        )
        assert "nix-cache.thoughtfull.systems-1:" in nix_conf, (
            "nix.conf should trust the cache signing key"
        )

    with subtest("no credentials: no system-pull timer or service"):
        noCredentials.fail("systemctl cat system-pull.timer")
        noCredentials.fail("systemctl cat system-pull.service")
        nix_conf = noCredentials.succeed("cat /etc/nix/nix.conf")
        print(f"noCredentials nix.conf:\n{nix_conf}")
        assert "s3://" not in nix_conf, (
            "without credentials, the s3 substituter should not be configured"
        )
  '';
}
