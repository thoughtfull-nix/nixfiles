{ nixpkgs, self, ... }:
let
  # Importing nixosModules/sway.nix requires lib.thoughtfull.dirFiles, and
  # module-set nixpkgs.overlays are ignored with external pkgs, so provide both
  # through the pkgs instance used by nixosTest.
  testPkgs = (nixpkgs.extend self.overlays.thoughtfull).extend (
    _: prev: {
      lib = prev.lib.extend (_: _: { thoughtfull = self.lib.thoughtfull; });
    }
  );
in
testPkgs.testers.nixosTest {
  name = "waybar";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    machine =
      { lib, pkgs, ... }:
      {
        imports = [
          # Import the real sway module so the waybar/gtk-defaults ordering test
          # exercises nixosModules/sway.nix instead of duplicating its unit
          # wiring here.
          ../nixosModules/sway.nix
          ../nixosModules/swayidle.nix
          # Define minimal options from unrelated thoughtfull modules so this
          # focused test does not need to import the full module set.
          {
            options.thoughtfull = {
              graphical.enable = lib.mkEnableOption "graphical UI configuration (stub)";
              impermanence.user.files = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
              programs.mako.enable = lib.mkEnableOption "mako (stub)";
              user.name = lib.mkOption {
                type = lib.types.str;
                default = "testuser";
              };
            };
          }
        ];

        # Configure thoughtfull user (required for the restart service)
        thoughtfull.user.name = "testuser";

        # Enable sway and waybar directly (bypassing the graphical module)
        programs.sway.enable = true;
        programs.waybar.enable = true;
        programs.yubikey-touch-detector.enable = true;

        # Make the displays widget's scripts callable from the test script.
        environment.systemPackages = [ pkgs.thoughtfull.waybar-displays ];

        # Create a test user for user services
        users.users.testuser = {
          isNormalUser = true;
          uid = 1000;
        };

        # A deliberately cyclic pair of units, used only as a positive
        # control for the "no ordering cycle" subtest below -- it proves
        # `systemd-analyze --user verify` actually detects cycles in this
        # environment, so a clean result on the real units can't be mistaken
        # for the check having silently failed to run.
        systemd.user.services.cycle-canary-a = {
          after = [ "cycle-canary-b.service" ];
          serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";
        };
        systemd.user.services.cycle-canary-b = {
          after = [ "cycle-canary-a.service" ];
          serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";
        };
      };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("yubikey-touch-detector service exists"):
        # Check that yubikey-touch-detector service file exists
        machine.succeed("test -f /etc/systemd/user/yubikey-touch-detector.service")

    with subtest("restart service exists with correct configuration"):
        # Check that the restart service exists as a system service
        machine.succeed("test -f /etc/systemd/system/restart-yubikey-touch-detector.service")

        # Verify the service has the correct Type
        result = machine.succeed("grep 'Type=oneshot' /etc/systemd/system/restart-yubikey-touch-detector.service")
        print(f"Service type: {result}")

        # Verify the service restarts yubikey-touch-detector for the correct user
        result = machine.succeed("grep 'ExecStart=.*systemctl.*--machine=testuser@.host.*--user.*restart yubikey-touch-detector.service' /etc/systemd/system/restart-yubikey-touch-detector.service")
        print(f"ExecStart: {result}")

    with subtest("restart service has correct dependencies"):
        # Verify After=suspend.target
        result = machine.succeed("grep 'After=.*suspend.target' /etc/systemd/system/restart-yubikey-touch-detector.service")
        print(f"After dependency: {result}")

        # Verify WantedBy=suspend.target
        result = machine.succeed("grep 'WantedBy=.*suspend.target' /etc/systemd/system/restart-yubikey-touch-detector.service")
        print(f"WantedBy dependency: {result}")

    with subtest("restart service is enabled"):
        # Check that the service symlink exists in suspend.target.wants
        machine.succeed("test -L /etc/systemd/system/suspend.target.wants/restart-yubikey-touch-detector.service")

    with subtest("restart service can execute successfully"):
        # Manually start the restart service to verify it works correctly
        # (Testing actual suspend/resume in QEMU is unreliable, but this verifies the core functionality)
        machine.succeed("systemctl start restart-yubikey-touch-detector.service")

        # Verify the service executed successfully by checking journalctl
        result = machine.succeed("journalctl -u restart-yubikey-touch-detector.service --no-pager")
        print(f"Service journal: {result}")

        # Verify the service completed successfully
        machine.succeed("journalctl -u restart-yubikey-touch-detector.service --no-pager | grep -q 'Starting Restart YubiKey touch detector after resume'")
        machine.succeed("journalctl -u restart-yubikey-touch-detector.service --no-pager | grep -q 'Finished Restart YubiKey touch detector after resume'")

    with subtest("waybar config wires up the displays widget"):
        # The displays module is present and placed after the tray.
        config = machine.succeed("cat /etc/xdg/waybar/config.jsonc")
        assert '"custom/displays"' in config, "custom/displays module missing"
        assert config.index('"tray"') < config.index('"custom/displays"'), (
            "custom/displays should come after tray in modules-right"
        )
        # It refreshes on a signal and, as a signal-driven module, also has a
        # polling interval so a missed signal self-heals.
        machine.succeed("grep -q '\"exec\": \"waybar-displays\"' /etc/xdg/waybar/config.jsonc")
        machine.succeed("grep -q '\"signal\": 4' /etc/xdg/waybar/config.jsonc")
        machine.succeed("grep -q '\"interval\": 60' /etc/xdg/waybar/config.jsonc")

    with subtest("waybar service PATH provides the widget's tooling"):
        # on-click launches wdisplays; exec runs waybar-displays (which also
        # bundles kanshi-toggle for on-click-right). NixOS renders the service
        # `path` into a PATH= line in a drop-in override, not the main unit.
        dropin = machine.succeed("cat /etc/systemd/user/waybar.service.d/*.conf")
        assert "waybar-displays" in dropin, "waybar-displays missing from waybar PATH"
        assert "wdisplays" in dropin, "wdisplays missing from waybar PATH"

    with subtest("waybar-displays reflects the active kanshi profile"):
        machine.succeed("mkdir -p /run/user/1000/kanshi")

        def displays_icon():
            return machine.succeed(
                "XDG_RUNTIME_DIR=/run/user/1000 waybar-displays"
            ).strip()

        machine.succeed("echo undocked > /run/user/1000/kanshi/active-profile")
        undocked = displays_icon()

        machine.succeed("echo docked > /run/user/1000/kanshi/active-profile")
        docked = displays_icon()

        assert undocked != docked, (
            f"docked and undocked should show different icons (got {undocked!r} / {docked!r})"
        )

        # An unknown/absent profile falls back to the undocked (laptop) icon.
        machine.succeed("rm -f /run/user/1000/kanshi/active-profile")
        assert displays_icon() == undocked, "missing profile should fall back to the undocked icon"

    with subtest("kanshi-active records the applied profile"):
        # pkill of a non-running waybar is tolerated (|| true), so this still
        # writes the state file that waybar-displays reads.
        machine.succeed("XDG_RUNTIME_DIR=/run/user/1000 kanshi-active undocked")
        machine.succeed("grep -qx undocked /run/user/1000/kanshi/active-profile")

    with subtest("gtk-defaults, waybar, and sway-session.target have no ordering cycle"):
        # `systemctl --user show` can't be queried without a live login
        # session, but `systemd-analyze --user verify` loads the same unit
        # graph in an offline test manager and reports cycles the same way
        # -- it just needs a writable XDG_RUNTIME_DIR, no session/bus.
        machine.succeed("install -d -o testuser -m 700 /tmp/verify-rt")

        def analyze_verify(units):
            _, output = machine.execute(
                "su testuser -c "
                f"'XDG_RUNTIME_DIR=/tmp/verify-rt systemd-analyze --user verify {units}' 2>&1"
            )
            return output

        # Positive control: prove verify actually detects a cycle in this
        # environment before trusting a clean result on the real units below
        # -- otherwise a broken invocation (wrong binary, bad XDG_RUNTIME_DIR,
        # su failing) would silently read as "no cycle found".
        canary_output = analyze_verify("cycle-canary-a.service cycle-canary-b.service")
        print("systemd-analyze --user verify (canary) output:")
        print(canary_output)
        assert "ordering cycle" in canary_output.lower(), (
            "self-test failed: systemd-analyze --user verify did not detect a "
            "deliberately cyclic pair of units, so the check below can't be trusted"
        )

        output = analyze_verify("waybar.service gtk-defaults.service sway-session.target")
        print("systemd-analyze --user verify output:")
        print(output)
        assert "ordering cycle" not in output.lower(), (
            "waybar/gtk-defaults/sway-session.target should not form an ordering cycle"
        )

    with subtest("sway-session.target is ordered after gtk-defaults applies the icon theme"):
        # gtk-defaults sets the GTK icon theme via gsettings. Rather than
        # every consumer ordering after gtk-defaults.service individually,
        # sway-session.target itself waits on it, so anything that just waits
        # on the target (waybar, pasystray, blueman-applet, ...) is covered.
        # Absence of a cycle above isn't enough to prove this edge exists --
        # e.g. a consumer silently losing its after=sway-session.target
        # wouldn't cycle, just quietly reintroduce the race -- so assert the
        # ordering direction directly on the rendered unit.
        target_unit = machine.succeed("cat /etc/systemd/user/sway-session.target")
        assert "gtk-defaults.service" in target_unit, (
            "sway-session.target should be ordered After=gtk-defaults.service"
        )

    with subtest("waybar and pasystray are ordered after sway-session.target"):
        # Same reasoning as above: confirm the consumer side of the edge
        # directly, rather than relying only on cycle-absence.
        dropin = machine.succeed("cat /etc/systemd/user/waybar.service.d/*.conf")
        assert "sway-session.target" in dropin, (
            "waybar should be ordered After=sway-session.target"
        )

        pasystray_unit = machine.succeed("cat /etc/systemd/user/pasystray.service")
        assert "sway-session.target" in pasystray_unit, (
            "pasystray should be ordered After=sway-session.target"
        )
  '';
}
