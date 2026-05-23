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

    with subtest("service uses agenix-decrypted EnvironmentFile"):
        unit = headless.succeed("systemctl cat system-pull.service")
        print(f"headless service:\n{unit}")
        assert "EnvironmentFile=/run/agenix/nix-cache-host-credentials" in unit, (
            "service should source AWS credentials from agenix path"
        )
        assert "ExecStart=" in unit and "/bin/system-pull thoughtfull-nix-cache us-east-1" in unit, (
            f"ExecStart should invoke system-pull with bucket and region; got:\n{unit}"
        )

    with subtest("switch-to-configuration runs in a transient unit detached from system-pull.service"):
        # The script must wrap switch-to-configuration with systemd-run so the
        # switch survives activation-time stop of system-pull.service itself.
        exec_start = headless.succeed(
            "systemctl show system-pull.service -p ExecStart --value"
        )
        script_path = exec_start.split("argv[]=")[1].split()[0]
        script = headless.succeed(f"cat {script_path}")
        print(f"system-pull script:\n{script}")
        # Strip comment lines so the ordering check isn't fooled by prose.
        code = "\n".join(
            line for line in script.splitlines() if not line.lstrip().startswith("#")
        )
        assert "systemd-run" in code, (
            "system-pull must invoke switch-to-configuration via systemd-run "
            "so activation can stop/restart system-pull.service without killing "
            "the in-flight switch"
        )
        assert "switch-to-configuration" in code, (
            "system-pull must invoke switch-to-configuration"
        )
        assert code.index("systemd-run") < code.index("switch-to-configuration"), (
            "systemd-run must wrap the switch-to-configuration invocation"
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
