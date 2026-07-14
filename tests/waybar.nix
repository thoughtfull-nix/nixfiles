{ nixpkgs, self, ... }:
nixpkgs.testers.nixosTest {
  name = "waybar";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    machine =
      { lib, pkgs, ... }:
      {
        imports = [
          # Import the sway/waybar module and its direct dependencies
          ../nixosModules/sway/waybar.nix
          # Define minimal thoughtfull.user option for the test
          {
            options.thoughtfull.user.name = lib.mkOption {
              type = lib.types.str;
              default = "testuser";
            };
          }
        ];

        # Apply the thoughtfull overlay to get pkgs.thoughtfull
        nixpkgs.overlays = [ self.overlays.thoughtfull ];

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

        # An unknown/absent profile falls back to the docked (monitor) icon.
        machine.succeed("rm -f /run/user/1000/kanshi/active-profile")
        assert displays_icon() == docked, "missing profile should fall back to the docked icon"

    with subtest("kanshi-active records the applied profile"):
        # pkill of a non-running waybar is tolerated (|| true), so this still
        # writes the state file that waybar-displays reads.
        machine.succeed("XDG_RUNTIME_DIR=/run/user/1000 kanshi-active undocked")
        machine.succeed("grep -qx undocked /run/user/1000/kanshi/active-profile")
  '';
}
