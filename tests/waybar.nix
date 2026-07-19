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

        # Make the displays widget's scripts callable from the test script, and pull in
        # netcat to fake the yubikey-touch-detector socket for the yubikey widget test.
        environment.systemPackages = [
          pkgs.netcat
          pkgs.thoughtfull.waybar-displays
        ];

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

        # Stub for the custom/network-vpn widget. Exercises the real
        # waybar-network-vpn/-toggle scripts against a real systemd unit
        # instead of the real wg-quick wiring (this focused test doesn't
        # import vpn.nix); polkit authorization for a non-root caller is
        # covered separately in tests/vpn.nix.
        systemd.services.vpn = {
          description = "Stub VPN service for waybar-network-vpn tests";
          serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        };
      };

    noVpn =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.thoughtfull.waybar-network ];
      };
  };

  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")
    noVpn.wait_for_unit("multi-user.target")

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

    with subtest("waybar-yubikey ignores broken multi-key HMAC events but still reports GPG/U2F"):
        # Regression test for a permanently-stuck "waiting for touch" indicator seen when
        # unplugging one of several YubiKeys. Root cause: yubikey-touch-detector's HMAC
        # detector infers touch-waiting from a global count of hidraw devices, which is
        # only valid with a single key (see nixosModules/sway/waybar.nix and
        # https://github.com/max-baz/yubikey-touch-detector/issues/62). We fake the
        # detector's unix socket here since no real hardware is available in the VM.
        # Use a throwaway XDG_RUNTIME_DIR (not /run/user/1000): the real
        # yubikey-touch-detector.socket unit is already socket-activated on that path,
        # so a second listener there would silently fail to bind.
        runtime_dir = "/tmp/yubikey-test-runtime"
        socket = f"{runtime_dir}/yubikey-touch-detector.socket"
        fifo = f"{runtime_dir}/yubikey-feed"
        out = "/tmp/yubikey-out.log"

        machine.succeed(f"mkdir -p {runtime_dir}")
        machine.succeed(f"mkfifo {fifo}")

        # Serve the fifo's contents over a listening unix socket, standing in for the
        # real daemon. Opening the fifo read-write keeps a reader attached so later
        # writes to it never block waiting for one.
        machine.execute(f"sh -c 'exec 3<>{fifo}; exec nc -lU {socket} <&3' >/tmp/fake-detector.log 2>&1 &")
        machine.wait_until_succeeds(f"test -S {socket}")

        machine.execute(f"XDG_RUNTIME_DIR={runtime_dir} timeout 30 waybar-yubikey >{out} 2>&1 &")
        machine.wait_until_succeeds(f"test -s {out}")  # initial idle line once connected

        def send(five_bytes):
            machine.succeed(f"printf '%s' '{five_bytes}' > {fifo}")

        def last_line():
            return machine.succeed(f"tail -n1 {out}").strip()

        # The bug: a lone MAC_1 (yubikey-touch-detector's broken multi-key HMAC signal)
        # must never surface as a tooltip.
        send("MAC_1")
        machine.succeed("sleep 1")
        machine.succeed(f"! grep -q tooltip {out}")

        # Real touch detection (GPG here, representative of GPG/U2F which are unaffected)
        # still works, and isn't disturbed by the ignored MAC_1 above.
        send("GPG_1")
        machine.wait_until_succeeds(f"grep -q tooltip {out}")
        assert "GPG" in last_line(), f"expected GPG in tooltip, got: {last_line()}"

        # Clearing GPG returns to idle; the stale MAC_1 does not resurrect the indicator.
        send("GPG_0")
        machine.wait_until_succeeds(f"tail -n1 {out} | grep -qv tooltip")

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

    with subtest("nm-applet is removed"):
        machine.fail("test -f /etc/systemd/user/nm-applet.service")

    with subtest("waybar config wires up the network widgets"):
        # Replaces nm-applet's tray icon with three custom modules: Wi-Fi,
        # Ethernet, and the wg-quick home VPN.
        config = machine.succeed("cat /etc/xdg/waybar/config.jsonc")
        for module in ["custom/network-wifi", "custom/network-ethernet", "custom/network-vpn"]:
            assert f'"{module}"' in config, f"{module} missing from config.jsonc"

        # Placed after battery, before tray -- the slot the old nm-applet
        # tray icon occupied.
        assert (
            config.index('"battery"')
            < config.index('"custom/network-wifi"')
            < config.index('"tray"')
        ), "network widgets should sit between battery and tray"

        for module in ["custom/network-wifi", "custom/network-ethernet", "custom/network-vpn"]:
            block = config[config.index(f'"{module}": {{') :]
            block = block[: block.index("\n  },")]
            assert '"format": "<span font=\\"20px\\">{}</span>"' in block, (
                f"{module} should use the same 20px icon format as theme/power"
            )

        machine.succeed('grep -q \'"exec": "waybar-network-wifi"\' /etc/xdg/waybar/config.jsonc')
        machine.succeed(
            'grep -q \'"on-click": "iwmenu --launcher fuzzel"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-middle": "waybar-network-wifi-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-right": "waybar-network-wifi-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed('grep -q \'"exec": "waybar-network-ethernet"\' /etc/xdg/waybar/config.jsonc')
        machine.succeed(
            'grep -q \'"on-click": "waybar-network-ethernet-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-middle": "waybar-network-ethernet-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-right": "nm-connection-editor -t 802-3-ethernet -s"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed('grep -q \'"exec": "waybar-network-vpn"\' /etc/xdg/waybar/config.jsonc')
        machine.succeed(
            'grep -q \'"on-click": "waybar-network-vpn-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-middle": "waybar-network-vpn-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-right": "waybar-network-vpn-toggle"\' /etc/xdg/waybar/config.jsonc'
        )

    with subtest("waybar service PATH provides the network widgets' tooling"):
        # PATH= only lists directories (nix store paths), one per package --
        # individual binary names inside a symlinkJoin bundle (like the six
        # waybar-network-* scripts, all joined under one "waybar-network"
        # output) don't appear literally, only the bundle's own name does.
        dropin = machine.succeed("cat /etc/systemd/user/waybar.service.d/*.conf")
        for tool in [
            "fuzzel",
            "iwmenu",
            "networkmanager",
            "network-manager-applet",
            "waybar-network",
        ]:
            assert tool in dropin, f"{tool} missing from waybar PATH"

    with subtest("network widgets use icon padding and no active background"):
        style = machine.succeed("cat /etc/xdg/waybar/style.css")
        assert (
            "#custom-network-wifi {\n  padding: 0 12pt 0 6pt;\n}"
            in style
        ), "Wi-Fi should use display-like right padding"
        assert (
            "#custom-network-ethernet,\n#custom-network-vpn,\n#mode"
            in style
        ), "Ethernet should use the default network widget padding"
        assert "#custom-network-ethernet {" not in style, (
            "Ethernet should use the default network widget padding"
        )
        assert "#custom-network-ethernet.connected" not in style, (
            "Ethernet should use the normal background when connected"
        )
        assert "#custom-network-vpn.connected" not in style, (
            "VPN should use the normal background when connected"
        )

    with subtest("waybar-network-wifi reports a disabled state when iwd is unavailable"):
        # This test node doesn't enable networking.wireless.iwd, so there's
        # no iwd daemon on the system bus for busctl to talk to -- the
        # widget should degrade gracefully rather than crash waybar's exec
        # loop. Wifi is queried via iwd directly (not nmcli/NetworkManager,
        # which only manages ethernet -- see graphical.nix and tests/graphical.nix).
        out = machine.succeed("waybar-network-wifi").strip()
        print(f"waybar-network-wifi output: {out}")
        status = json.loads(out)
        assert status["class"] == "disabled", f"expected a disabled state, got: {out}"
        assert status["text"] == "󰤯", f"expected icon-only Wi-Fi text, got: {out}"

        waybar_network_dir = machine.succeed(
            "dirname $(readlink -f $(command -v waybar-network-wifi))"
        ).strip()
        for icon in ["󰤟", "󰤢", "󰤥", "󰤨"]:
            machine.succeed(f"grep -R -q '{icon}' {waybar_network_dir}")

    with subtest(
        "waybar-network-ethernet reports a disabled state when NetworkManager is unavailable"
    ):
        out = machine.succeed("waybar-network-ethernet").strip()
        print(f"waybar-network-ethernet output: {out}")
        status = json.loads(out)
        assert status["class"] == "disabled", f"expected a disabled state, got: {out}"
        assert status["text"] == "󰈀", f"expected icon-only Ethernet text, got: {out}"

    with subtest("waybar-network-vpn is disabled when vpn.service is absent"):
        out = noVpn.succeed("waybar-network-vpn").strip()
        status = json.loads(out)
        assert status["class"] == "disabled", f"expected disabled, got: {out}"
        assert status["text"] == "󰦝", f"expected icon-only VPN text, got: {out}"
        noVpn.succeed("waybar-network-vpn-toggle")

    with subtest("waybar-network-vpn reflects and toggles a real systemd unit"):
        machine.succeed("systemctl stop vpn.service || true")

        out = machine.succeed("waybar-network-vpn").strip()
        status = json.loads(out)
        assert status["class"] == "disconnected", f"expected disconnected, got: {out}"
        assert status["text"] == "󰦝", f"expected icon-only VPN text, got: {out}"

        machine.succeed("waybar-network-vpn-toggle")
        machine.succeed("systemctl is-active --quiet vpn.service")
        out = machine.succeed("waybar-network-vpn").strip()
        status = json.loads(out)
        assert status["class"] == "connected", f"expected connected, got: {out}"
        assert status["text"] == "󰦝", f"expected icon-only VPN text, got: {out}"

        machine.succeed("waybar-network-vpn-toggle")
        machine.fail("systemctl is-active --quiet vpn.service")
        out = machine.succeed("waybar-network-vpn").strip()
        status = json.loads(out)
        assert status["class"] == "disconnected", f"expected disconnected again, got: {out}"
        assert status["text"] == "󰦝", f"expected icon-only VPN text, got: {out}"
  '';
}
