{ nixpkgs, ... }:
let
  # Stub thoughtfull.graphical.enable so the auto-upgrade module can branch on
  # it without pulling in nixosModules/graphical.nix (which depends on other
  # internal modules like impermanence).
  graphicalStub =
    { lib, ... }:
    {
      options.thoughtfull.graphical.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
in
nixpkgs.testers.nixosTest {
  name = "auto-upgrade";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    graphical = {
      imports = [
        ../nixosModules/auto-upgrade.nix
        graphicalStub
      ];
      thoughtfull.graphical.enable = true;
      # Default is disabled; opt back in for this test node.
      system.autoUpgrade.enable = true;
    };

    headless = {
      imports = [
        ../nixosModules/auto-upgrade.nix
        graphicalStub
      ];
      # graphical.enable stays false
      system.autoUpgrade.enable = true;
    };

    defaultDisabled = {
      imports = [
        ../nixosModules/auto-upgrade.nix
        graphicalStub
      ];
      # No override; should land on the module default of disabled.
    };
  };

  testScript = ''
    import re

    def upgrade_script(machine):
        # NixOS encodes `script = "..."` services as a wrapper executable at
        # the ExecStart path. The actual `nixos-rebuild` invocation lives in
        # that file, not in the unit text.
        unit = machine.succeed("systemctl cat nixos-upgrade.service")
        m = re.search(r"^ExecStart=(\S+)", unit, re.MULTILINE)
        assert m, f"could not parse ExecStart from unit:\n{unit}"
        return machine.succeed(f"cat {m.group(1)}")

    start_all()
    graphical.wait_for_unit("multi-user.target")
    headless.wait_for_unit("multi-user.target")
    defaultDisabled.wait_for_unit("multi-user.target")

    with subtest("graphical default: timer fires at noon"):
        timer = graphical.succeed("systemctl cat nixos-upgrade.timer")
        print(f"graphical timer:\n{timer}")
        assert "OnCalendar=*-*-* 12:00:00" in timer, (
            "graphical host should fire at noon"
        )
        assert "RandomizedDelaySec=15min" in timer, (
            "should have 15min randomized delay"
        )

    with subtest("graphical default: does not allow reboot"):
        script = upgrade_script(graphical)
        print(f"graphical script:\n{script}")
        # When allowReboot=false, upstream emits `nixos-rebuild switch ...`
        # directly and never invokes `shutdown -r`.
        assert "shutdown -r" not in script, (
            "graphical host must not schedule a reboot"
        )
        assert "nixos-rebuild boot" not in script, (
            "graphical host should use 'switch', not 'boot'"
        )

    with subtest("headless default: timer fires at 3am"):
        timer = headless.succeed("systemctl cat nixos-upgrade.timer")
        print(f"headless timer:\n{timer}")
        assert "OnCalendar=*-*-* 03:00:00" in timer, (
            "headless host should fire at 3am"
        )

    with subtest("headless default: allows reboot"):
        script = upgrade_script(headless)
        print(f"headless script:\n{script}")
        # When allowReboot=true, upstream's script first does `nixos-rebuild
        # boot ...` and conditionally `shutdown -r +1`.
        assert "nixos-rebuild boot" in script, (
            "headless host should use 'boot' to stage kernel updates"
        )
        assert "shutdown -r" in script, (
            "headless host should schedule a reboot when kernel changed"
        )

    with subtest("default flake URL points to thoughtfull-nix/nixfiles"):
        script = upgrade_script(graphical)
        assert "--flake github:thoughtfull-nix/nixfiles" in script, (
            "default flake should be github:thoughtfull-nix/nixfiles"
        )

    with subtest("default: timer and service do not exist (build-and-push is the primary path)"):
        defaultDisabled.fail("systemctl cat nixos-upgrade.timer")
        defaultDisabled.fail("systemctl cat nixos-upgrade.service")
  '';
}
