{ nixpkgs, self, ... }:
let
  stubs = import ./stubs.nix;

  # Importing nixosModules/sway.nix requires lib.thoughtfull.dirFiles, and
  # module-set nixpkgs.overlays are ignored with external pkgs, so provide both
  # through the pkgs instance used by nixosTest.
  testPkgs = (nixpkgs.extend self.overlays.thoughtfull).extend (
    _: prev: {
      lib = prev.lib.extend (_: _: { thoughtfull = self.lib.thoughtfull; });
    }
  );

  # Fixture nmcli output for the ethernet-menu and wifi-menu regression tests
  # below, dispatched on the full argument string (mirroring stubPactl's
  # `case "$*"` style further down) since both menus now issue several
  # distinct `-t`/`-g` queries that each need their own canned response.
  stubNmcli = testPkgs.writeShellScriptBin "nmcli" ''
    set -euo pipefail
    echo "nmcli $*" >>/tmp/nmcli-calls.log
    case "$*" in
      # ethernet-menu.bash's connection list: one already-connected profile,
      # plus profiles whose NAME exercises nmcli's terse-output escaping (an
      # escaped colon, an escaped backslash, and both adjacent to each
      # other) that ethernet-menu.bash must undo when it displays the name.
      "-t -f UUID,TYPE,DEVICE,NAME connection show")
        printf '%s\n' \
          'uuid-plain:802-3-ethernet:eth0:Plain' \
          'uuid-colon:802-3-ethernet::foo\:bar' \
          'uuid-backslash:802-3-ethernet::back\\slash' \
          'uuid-both:802-3-ethernet::a\\\:b'
        ;;
      # network-device.bash's device list, shared by wifi-status/-toggle/-menu.
      "-t -f DEVICE,TYPE,STATE device status")
        printf '%s\n' \
          'eth0:ethernet:connected' \
          'wlan0:wifi:connected'
        ;;
      "-g WIFI general status")
        echo "enabled"
        ;;
      # wifi-menu.bash's known-network profiles, keyed by uuid rather than
      # NAME -- two profiles, one for the network currently in range and
      # connected, one for a known network that isn't.
      "-t -f UUID,TYPE connection show")
        printf '%s\n' \
          'wifi-uuid-known-connected:802-11-wireless' \
          'wifi-uuid-known-other:802-11-wireless'
        ;;
      "--escape no -g 802-11-wireless.ssid connection show wifi-uuid-known-connected")
        echo "Known Connected"
        ;;
      "--escape no -g 802-11-wireless.ssid connection show wifi-uuid-known-other")
        echo "Known Other"
        ;;
      "-g connection.autoconnect connection show wifi-uuid-known-connected")
        echo "yes"
        ;;
      "-g connection.autoconnect connection show wifi-uuid-known-other")
        echo "no"
        ;;
      # wifi-status.bash's scan list: just the in-use AP.
      "--escape no -t -f IN-USE,SIGNAL,SSID device wifi list ifname wlan0")
        echo '*:90:Known Connected'
        ;;
      # wifi-menu.bash's scan list: the two known networks above (one
      # in-use), plus a secure and an open network with no saved profile.
      # "New Strong" outranks every known network on raw signal (95 vs 90/60)
      # but has no saved profile -- nmcli's own signal-sorted order lists it
      # first, so it's the case that actually distinguishes "known networks
      # before new ones" (what this menu must do, matching iwmenu) from
      # "raw signal order" (what a naive pass-through would do instead).
      # "Known Connected" also gets a second, stronger BSSID row that isn't
      # the one actually in use (a mesh/repeater AP broadcasting the same
      # SSID) -- regression fixture for a real bug where keeping only the
      # first-seen row per SSID silently dropped the in-use marker whenever
      # that first row wasn't the connected one.
      "--escape no -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list ifname wlan0")
        printf '%s\n' \
          ':95:WPA2:New Strong' \
          ':92:WPA2:Known Connected' \
          '*:90:WPA2:Known Connected' \
          ':60:--:Known Other' \
          ':40:WPA2:Secure New' \
          ':30:--:Open New'
        ;;
      # "Known Other" starts with autoconnect=no (see the connection.autoconnect
      # fixture above), so toggling it tries to turn autoconnect *on* --
      # fixture-rigged to fail, for the regression test below that this
      # must not flip the script's own local known_autoconnect state when
      # nmcli itself reports the change never took.
      "connection modify uuid wifi-uuid-known-other connection.autoconnect yes")
        exit 1
        ;;
      *) ;;
    esac
  '';

  # Stands in for the interactive fuzzel picker. Logs whatever menu it was
  # shown (the thing under test -- this is how the ethernet-menu.bash
  # regression test below observes the decoded profile names without a real
  # Wayland session) and answers from a queue of 1-based line numbers in
  # $FUZZEL_ANSWERS, one per invocation; "CANCEL" reproduces fuzzel's
  # non-zero dmenu-cancel exit code instead of picking a line, and
  # "TYPE:<text>" reproduces fuzzel's dmenu-mode behavior of returning
  # whatever was typed when it doesn't match any candidate -- real fuzzel
  # does this for wifi-menu.bash's passphrase prompt, which shows no
  # candidates at all (empty stdin) for the user to type into.
  stubFuzzel = testPkgs.writeShellScriptBin "fuzzel" ''
    set -euo pipefail
    input=$(cat)
    {
      echo "== fuzzel $* =="
      printf '%s\n' "$input"
    } >>"$FUZZEL_LOG"

    choice=$(head -n1 "$FUZZEL_ANSWERS")
    sed -i '1d' "$FUZZEL_ANSWERS"

    [[ ''${choice} == "CANCEL" ]] && exit 2

    if [[ ''${choice} == TYPE:* ]]; then
      printf '%s\n' "''${choice#TYPE:}"
      exit 0
    fi

    for arg in "$@"; do
      if [[ ''${arg} == "--index" ]]; then
        echo $((choice - 1))
        exit 0
      fi
    done
    printf '%s\n' "$input" | sed -n "''${choice}p"
  '';

  stubNmConnectionEditor = testPkgs.writeShellScriptBin "nm-connection-editor" ''
    echo "nm-connection-editor $*" >>/tmp/nmcli-calls.log
  '';

  # The real ethernet-menu.bash rebuilt with nmcli/fuzzel replaced by the
  # stubs above, so its parsing/escaping/index-lookup logic can be exercised
  # end to end without real NetworkManager or a Wayland compositor.
  testEthernetMenu = testPkgs.thoughtfull.writeFileScriptBin {
    name = "waybar-network-ethernet-menu-test";
    replacements = {
      bash = "${testPkgs.bash}/bin/bash";
      fuzzel = "${stubFuzzel}/bin/fuzzel";
      "nm-connection-editor" = "${stubNmConnectionEditor}/bin/nm-connection-editor";
      nmcli = "${stubNmcli}/bin/nmcli";
    };
    src = ../packages/waybar-network/ethernet-menu.bash;
  };

  # network-device.bash rebuilt against stubNmcli, so wifi-menu-test below
  # (which shares this device-discovery helper with the real
  # waybar-network-wifi/-toggle) resolves "wlan0" from the same fixture data
  # instead of querying real hardware.
  testNetworkDevice = testPkgs.thoughtfull.writeFileScriptBin {
    name = "waybar-network-device-test";
    replacements = {
      awk = "${testPkgs.gawk}/bin/awk";
      bash = "${testPkgs.bash}/bin/bash";
      nmcli = "${stubNmcli}/bin/nmcli";
    };
    src = ../packages/waybar-network/network-device.bash;
  };

  # The real wifi-menu.bash rebuilt with nmcli/fuzzel/nm-connection-editor
  # replaced by the stubs above (and network-device pointed at the
  # stub-wired build just above), exercising the real known/new-network
  # join, submenu, and passphrase-prompt logic end to end.
  testWifiMenu = testPkgs.thoughtfull.writeFileScriptBin {
    name = "waybar-network-wifi-menu-test";
    replacements = {
      bash = "${testPkgs.bash}/bin/bash";
      fuzzel = "${stubFuzzel}/bin/fuzzel";
      "network-device" = "${testNetworkDevice}/bin/waybar-network-device-test";
      "nm-connection-editor" = "${stubNmConnectionEditor}/bin/nm-connection-editor";
      nmcli = "${stubNmcli}/bin/nmcli";
      systemctl = "${testPkgs.systemd}/bin/systemctl";
    };
    src = ../packages/waybar-network/wifi-menu.bash;
  };

  # Stateful nmcli stub for the wifi-menu radio-poll regression test below:
  # unlike stubNmcli above (a stateless case dispatch), the device-status
  # response here has to change across repeated calls within a single
  # script run, to simulate the driver actually coming up after `radio
  # wifi on` rather than being ready immediately.
  stubNmcliRadioPoll = testPkgs.writeShellScriptBin "nmcli" ''
    set -euo pipefail
    echo "nmcli $*" >>/tmp/nmcli-calls.log
    case "$*" in
      "-g WIFI general status")
        if [[ -f /tmp/radio-poll-on ]]; then
          echo "enabled"
        else
          echo "disabled"
        fi
        ;;
      "radio wifi on")
        touch /tmp/radio-poll-on
        ;;
      "-t -f DEVICE,TYPE,STATE device status")
        # nmcli lists a wifi device regardless of whether the radio is
        # powered (DEVICE is always present), but STATE stays "unavailable"
        # until the driver actually comes up -- for the first two calls
        # here, then "disconnected" (ready) from the third call on, so a
        # caller that polls STATE itself (not just device presence, which
        # is already true on the very first call) has to loop more than
        # once before it sees readiness.
        count_file=/tmp/radio-poll-status-calls
        count=$(($(cat "''${count_file}" 2>/dev/null || echo 0) + 1))
        echo "''${count}" >"''${count_file}"
        if ((count < 3)); then
          echo "wlan0:wifi:unavailable"
        else
          echo "wlan0:wifi:disconnected"
        fi
        ;;
      "-t -f UUID,TYPE connection show") ;;
      "--escape no -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list ifname wlan0")
        echo ':50:--:Ready Network'
        ;;
      *) ;;
    esac
  '';

  # network-device.bash and wifi-menu.bash rebuilt against stubNmcliRadioPoll
  # instead of stubNmcli, so this one scenario's stateful device-status
  # progression doesn't have to be threaded through the shared stub above
  # (which every other wifi-menu/status/toggle test also relies on staying
  # simple and stateless).
  testNetworkDeviceRadioPoll = testPkgs.thoughtfull.writeFileScriptBin {
    name = "waybar-network-device-radio-poll-test";
    replacements = {
      awk = "${testPkgs.gawk}/bin/awk";
      bash = "${testPkgs.bash}/bin/bash";
      nmcli = "${stubNmcliRadioPoll}/bin/nmcli";
    };
    src = ../packages/waybar-network/network-device.bash;
  };
  testWifiMenuRadioPoll = testPkgs.thoughtfull.writeFileScriptBin {
    name = "waybar-network-wifi-menu-radio-poll-test";
    replacements = {
      bash = "${testPkgs.bash}/bin/bash";
      fuzzel = "${stubFuzzel}/bin/fuzzel";
      "network-device" = "${testNetworkDeviceRadioPoll}/bin/waybar-network-device-radio-poll-test";
      "nm-connection-editor" = "${stubNmConnectionEditor}/bin/nm-connection-editor";
      nmcli = "${stubNmcliRadioPoll}/bin/nmcli";
      systemctl = "${testPkgs.systemd}/bin/systemctl";
    };
    src = ../packages/waybar-network/wifi-menu.bash;
  };

  # Fixture-driven stand-in for pactl, used by the audio widget script tests
  # below. Every invocation is logged (mirroring stubNmcli) so tests can
  # assert on set-default-sink/move-sink-input calls without a real
  # PipeWire/PulseAudio server; the handful of read commands the audio
  # scripts depend on answer from files each subtest points at via env vars,
  # so different subtests can swap in different fixtures without rebuilding
  # the stub.
  stubPactl = testPkgs.writeShellScriptBin "pactl" ''
    set -euo pipefail
    echo "pactl $*" >>/tmp/pactl-calls.log
    case "$*" in
      "-f json list sinks") cat "''${SINKS_JSON:-/dev/null}" ;;
      "-f json list sources") cat "''${SOURCES_JSON:-/dev/null}" ;;
      "get-default-sink") cat "''${DEFAULT_SINK_FILE:-/dev/null}" ;;
      "get-default-source") cat "''${DEFAULT_SOURCE_FILE:-/dev/null}" ;;
      "list sink-inputs short") cat "''${SINK_INPUTS:-/dev/null}" ;;
      "list source-outputs short") cat "''${SOURCE_OUTPUTS:-/dev/null}" ;;
      *) ;;
    esac
  '';

  # The real status/menu scripts rebuilt with pactl/fuzzel replaced by the
  # stubs above (jq and systemctl are the real thing -- deterministic and
  # harmless against the test machine's real waybar service, same as the
  # network widget tests leave them unstubbed).
  testSpeakerStatus = testPkgs.thoughtfull.writeFileScriptBin {
    name = "waybar-audio-speaker-test";
    replacements = {
      bash = "${testPkgs.bash}/bin/bash";
      jq = "${testPkgs.jq}/bin/jq";
      pactl = "${stubPactl}/bin/pactl";
    };
    src = ../packages/waybar-audio/speaker-status.bash;
  };
  testMicStatus = testPkgs.thoughtfull.writeFileScriptBin {
    name = "waybar-audio-mic-test";
    replacements = {
      bash = "${testPkgs.bash}/bin/bash";
      jq = "${testPkgs.jq}/bin/jq";
      pactl = "${stubPactl}/bin/pactl";
    };
    src = ../packages/waybar-audio/mic-status.bash;
  };
  testSpeakerMenu = testPkgs.thoughtfull.writeFileScriptBin {
    name = "waybar-audio-speaker-menu-test";
    replacements = {
      bash = "${testPkgs.bash}/bin/bash";
      fuzzel = "${stubFuzzel}/bin/fuzzel";
      jq = "${testPkgs.jq}/bin/jq";
      pactl = "${stubPactl}/bin/pactl";
      systemctl = "${testPkgs.systemd}/bin/systemctl";
    };
    src = ../packages/waybar-audio/speaker-menu.bash;
  };
  testMicMenu = testPkgs.thoughtfull.writeFileScriptBin {
    name = "waybar-audio-mic-menu-test";
    replacements = {
      bash = "${testPkgs.bash}/bin/bash";
      fuzzel = "${stubFuzzel}/bin/fuzzel";
      jq = "${testPkgs.jq}/bin/jq";
      pactl = "${stubPactl}/bin/pactl";
      systemctl = "${testPkgs.systemd}/bin/systemctl";
    };
    src = ../packages/waybar-audio/mic-menu.bash;
  };
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
          # Stubs for unrelated thoughtfull modules so this focused test does not
          # need to import the full module set.
          stubs.graphicalEnable
          stubs.impermanence
          # Remaining minimal options not covered by shared stubs.
          {
            options.thoughtfull = {
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
          testEthernetMenu
          testMicMenu
          testMicStatus
          testNetworkDevice
          testSpeakerMenu
          testSpeakerStatus
          testWifiMenu
          testWifiMenuRadioPoll
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
    import shlex

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

    with subtest("waybar config restarts the yubikey widget if it exits"):
        # custom/yubikey has no signal/interval, so waybar treats it as a
        # continuous script and won't ever re-launch it if the process exits
        # -- unlike the socket disappearing/reappearing, which the script's
        # own outer retry loop already handles internally. restart-interval
        # is the config-level safety net for the script crashing outright.
        config = machine.succeed("cat /etc/xdg/waybar/config.jsonc")
        block = config[config.index('"custom/yubikey": {') :]
        block = block[: block.index("\n  },")]
        assert '"restart-interval"' in block, (
            "custom/yubikey should set restart-interval so waybar respawns it if it exits"
        )

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
        # on the target (waybar, blueman-applet, ...) is covered. Absence of
        # a cycle above isn't enough to prove this edge exists -- e.g. a
        # consumer silently losing its after=sway-session.target wouldn't
        # cycle, just quietly reintroduce the race -- so assert the ordering
        # direction directly on the rendered unit.
        target_unit = machine.succeed("cat /etc/systemd/user/sway-session.target")
        assert "gtk-defaults.service" in target_unit, (
            "sway-session.target should be ordered After=gtk-defaults.service"
        )

    with subtest("waybar is ordered after sway-session.target"):
        # Same reasoning as above: confirm the consumer side of the edge
        # directly, rather than relying only on cycle-absence.
        dropin = machine.succeed("cat /etc/systemd/user/waybar.service.d/*.conf")
        assert "sway-session.target" in dropin, (
            "waybar should be ordered After=sway-session.target"
        )

    with subtest("nm-applet is removed"):
        machine.fail("test -f /etc/systemd/user/nm-applet.service")

    with subtest("pasystray is not installed or managed"):
        # Replaced by the custom/audio-mic and custom/audio-speaker widgets
        # below -- no tray icon, no user service, no package.
        machine.fail("test -f /etc/systemd/user/pasystray.service")
        machine.fail("command -v pasystray")

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
        # wifi-toggle.bash and wifi-menu.bash both poke this signal after
        # changing state, so the icon updates immediately instead of
        # waiting out the 15s poll interval.
        machine.succeed('grep -q \'"signal": 5\' /etc/xdg/waybar/config.jsonc')
        machine.succeed(
            'grep -q \'"on-click": "waybar-network-wifi-menu"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-middle": "waybar-network-wifi-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-right": "waybar-network-wifi-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed('grep -q \'"exec": "waybar-network-ethernet"\' /etc/xdg/waybar/config.jsonc')
        machine.succeed(
            'grep -q \'"on-click": "waybar-network-ethernet-menu"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-middle": "waybar-network-ethernet-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-right": "waybar-network-ethernet-toggle"\' /etc/xdg/waybar/config.jsonc'
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

    with subtest("waybar config wires up the audio widgets"):
        # Replaces pasystray's tray icon with two custom modules: mic and
        # speaker. Placed after the network widgets, before tray -- the slot
        # the old pasystray tray icon occupied.
        config = machine.succeed("cat /etc/xdg/waybar/config.jsonc")
        for module in ["custom/audio-mic", "custom/audio-speaker"]:
            assert f'"{module}"' in config, f"{module} missing from config.jsonc"

        assert (
            config.index('"custom/network-vpn"')
            < config.index('"custom/audio-mic"')
            < config.index('"tray"')
        ), "audio widgets should sit between the network widgets and tray"

        for module in ["custom/audio-mic", "custom/audio-speaker"]:
            block = config[config.index(f'"{module}": {{') :]
            block = block[: block.index("\n  },")]
            assert '"format": "<span font=\\"20px\\">{}</span>"' in block, (
                f"{module} should use the same 20px icon format as theme/power"
            )

        machine.succeed('grep -q \'"exec": "waybar-audio-mic"\' /etc/xdg/waybar/config.jsonc')
        # mic-menu.bash and mic-toggle.bash both poke this signal after
        # changing state, so the icon updates immediately instead of
        # waiting out the 15s poll interval.
        machine.succeed('grep -q \'"signal": 7\' /etc/xdg/waybar/config.jsonc')
        machine.succeed(
            'grep -q \'"on-click": "waybar-audio-mic-menu"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-middle": "waybar-audio-mic-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-right": "waybar-audio-mic-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed('grep -q \'"exec": "waybar-audio-speaker"\' /etc/xdg/waybar/config.jsonc')
        machine.succeed('grep -q \'"signal": 6\' /etc/xdg/waybar/config.jsonc')
        machine.succeed(
            'grep -q \'"on-click": "waybar-audio-speaker-menu"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-middle": "waybar-audio-speaker-toggle"\' /etc/xdg/waybar/config.jsonc'
        )
        machine.succeed(
            'grep -q \'"on-click-right": "waybar-audio-speaker-toggle"\' /etc/xdg/waybar/config.jsonc'
        )

    with subtest("waybar service PATH provides the network widgets' tooling"):
        # PATH= only lists directories (nix store paths), one per package --
        # individual binary names inside a symlinkJoin bundle (like the six
        # waybar-network-* scripts, all joined under one "waybar-network"
        # output) don't appear literally, only the bundle's own name does.
        dropin = machine.succeed("cat /etc/systemd/user/waybar.service.d/*.conf")
        for tool in [
            "fuzzel",
            "networkmanager",
            "network-manager-applet",
            "waybar-network",
        ]:
            assert tool in dropin, f"{tool} missing from waybar PATH"

    with subtest("waybar service PATH provides the audio widgets' tooling"):
        dropin = machine.succeed("cat /etc/systemd/user/waybar.service.d/*.conf")
        for tool in ["fuzzel", "pulseaudio", "waybar-audio"]:
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

    with subtest("audio widgets use the default padding and dim when muted/disabled"):
        style = machine.succeed("cat /etc/xdg/waybar/style.css")
        assert "#custom-audio-mic,\n#custom-audio-speaker" in style, (
            "audio widgets should use the default network widget padding"
        )
        assert "#custom-audio-mic.muted" in style, "muted mic should be dimmed"
        assert "#custom-audio-speaker.muted" in style, "muted speaker should be dimmed"
        assert "#custom-audio-mic.disabled" in style, "disabled mic should be dimmed"
        assert "#custom-audio-speaker.disabled" in style, "disabled speaker should be dimmed"

    with subtest("waybar-network-wifi reports a disabled state when NetworkManager is unavailable"):
        # This test node never sets networking.networkmanager.enable, so
        # nmcli exists on PATH (installed unconditionally by waybar.nix) but
        # there's no live NetworkManager D-Bus service for it to talk to --
        # the widget should degrade gracefully rather than crash waybar's
        # exec loop, exactly like the Ethernet widget below.
        out = machine.succeed("waybar-network-wifi").strip()
        print(f"waybar-network-wifi output: {out}")
        status = json.loads(out)
        assert status["class"] == "disabled", f"expected a disabled state, got: {out}"
        assert status["text"] == "󰤭", f"expected the slashed Wi-Fi icon, got: {out}"

        waybar_network_dir = machine.succeed(
            "dirname $(readlink -f $(command -v waybar-network-wifi))"
        ).strip()
        for icon in ["󰤟", "󰤢", "󰤥", "󰤨", "󰤯", "󰤭"]:
            machine.succeed(f"grep -R -q '{icon}' {waybar_network_dir}")

    with subtest(
        "waybar-network-wifi-menu lists Scan/known/new networks and manages known-network connections"
    ):
        # Exercises the real script (waybar-network-wifi-menu-test, built
        # from the same source as waybar-network-wifi-menu but with
        # nmcli/fuzzel/nm-connection-editor replaced by stubs -- see
        # stubNmcli/stubFuzzel/testNetworkDevice above) against fixture
        # nmcli output, without real NetworkManager hardware or a Wayland
        # compositor.
        fuzzel_log = "/tmp/fuzzel-wifi-menu.log"
        answers = "/tmp/fuzzel-wifi-answers"

        def run_wifi_menu(*choices):
            machine.succeed(f"rm -f {fuzzel_log} /tmp/nmcli-calls.log")
            machine.succeed("printf '%s\\n' " + " ".join(choices) + f" >{answers}")
            machine.succeed(
                f"FUZZEL_LOG={fuzzel_log} FUZZEL_ANSWERS={answers} "
                "waybar-network-wifi-menu-test"
            )

        # Cancelling the very first prompt is enough to inspect the
        # top-level list: Scan first, then known networks before new ones,
        # then Settings last. "New Strong" has the strongest raw signal of
        # any fixture network (95%) but no saved profile, so it landing
        # after both known networks (rather than first, which is where
        # nmcli's own signal-sorted scan order would put it) is what proves
        # this groups known-before-new like iwmenu does, rather than just
        # passing nmcli's order straight through. The currently connected
        # known network also carries iwmenu's trailing connected marker.
        run_wifi_menu("CANCEL")
        top_level = machine.succeed(f"cat {fuzzel_log}")
        for label in ["Scan", "Known Connected", "Known Other", "New Strong", "Secure New", "Open New", "Settings"]:
            assert label in top_level, f"expected {label!r} in the main menu, got: {top_level}"
        assert (
            top_level.index("Scan")
            < top_level.index("Known Connected")
            < top_level.index("Known Other")
            < top_level.index("New Strong")
            < top_level.index("Settings")
        ), (
            f"expected Scan, then known networks, then new networks (New Strong "
            f"included, despite outranking every known network on signal), then "
            f"Settings, got: {top_level}"
        )
        assert "Known Connected ⏺" in top_level, (
            f"the connected network should carry the connected marker, got: {top_level}"
        )

        # "Scan" in top_level above is a substring match, so it alone can't
        # tell an icon-prefixed line ("<icon> Scan") apart from a bare one
        # with no icon at all (" Scan", from an empty icon_scan) --
        # regression test for exactly that: icon_scan was left empty while
        # every other icon_* in the script carried a real glyph.
        scan_line = next(line for line in top_level.splitlines() if line.endswith("Scan"))
        assert not scan_line.startswith(" "), (
            f"Scan should be prefixed by an icon, not a bare leading space, got: {scan_line!r}"
        )

        # Selecting the connected known network (list line 2, since Scan is
        # line 1) then Disconnect (submenu line 1) resolves to its uuid via
        # --index, not label text.
        run_wifi_menu("2", "1")
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "connection down uuid wifi-uuid-known-connected" in calls, (
            f"expected disconnect call, got: {calls}"
        )

        # Selecting the disconnected known network (list line 3) then
        # Connect (submenu line 1) does the opposite. ifname must be passed
        # explicitly here -- regression test for a real bug where its
        # absence made nmcli's automatic device selection skip wlan0
        # whenever it was already active with a different network (exactly
        # the case this menu item exists for) and fail instead of
        # switching it over.
        run_wifi_menu("3", "1")
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "connection up uuid wifi-uuid-known-other ifname wlan0" in calls, (
            f"expected connect call targeting wlan0 explicitly, got: {calls}"
        )

        # Forgetting a known network (submenu line 2) deletes the right
        # uuid, not a neighboring one.
        run_wifi_menu("3", "2")
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "connection delete uuid wifi-uuid-known-other" in calls, (
            f"expected forget/delete call, got: {calls}"
        )

    with subtest(
        "waybar-network-wifi-menu keeps the autoconnect label in sync when nmcli modify fails"
    ):
        fuzzel_log = "/tmp/fuzzel-wifi-menu.log"
        answers = "/tmp/fuzzel-wifi-answers"

        def run_wifi_menu(*choices):
            machine.succeed(f"rm -f {fuzzel_log} /tmp/nmcli-calls.log")
            machine.succeed("printf '%s\\n' " + " ".join(choices) + f" >{answers}")
            machine.succeed(
                f"FUZZEL_LOG={fuzzel_log} FUZZEL_ANSWERS={answers} "
                "waybar-network-wifi-menu-test"
            )

        # Known Other (top-level line 3) starts with autoconnect=no, so its
        # submenu opens on "Enable autoconnect" (submenu line 3). Selecting
        # it triggers a `connection modify ... autoconnect yes` call that
        # the fixture nmcli is rigged to fail, then Back (submenu line 4,
        # since toggling redisplays the same submenu rather than exiting)
        # to inspect the label without ever exiting the script.
        run_wifi_menu("3", "3", "4")
        submenu_log = machine.succeed(f"cat {fuzzel_log}")
        # The submenu is shown twice: once before the failed toggle, once
        # after. Both should still say "Enable autoconnect" -- if the
        # script's local state had flipped despite nmcli reporting failure,
        # the second showing would say "Disable autoconnect" instead.
        assert submenu_log.count("Enable autoconnect") == 2, (
            f"expected the autoconnect label to stay in sync after a failed "
            f"modify call, got: {submenu_log}"
        )
        assert "Disable autoconnect" not in submenu_log, (
            f"local autoconnect state should not flip when nmcli modify "
            f"fails, got: {submenu_log}"
        )

    with subtest(
        "waybar-network-wifi-menu connects to new networks, prompting for a passphrase only when secure"
    ):
        fuzzel_log = "/tmp/fuzzel-wifi-menu.log"
        answers = "/tmp/fuzzel-wifi-answers"

        def run_wifi_menu(*choices):
            machine.succeed(f"rm -f {fuzzel_log} /tmp/nmcli-calls.log")
            machine.succeed("printf '%s\\n' " + " ".join(choices) + f" >{answers}")
            machine.succeed(
                f"FUZZEL_LOG={fuzzel_log} FUZZEL_ANSWERS={answers} "
                "waybar-network-wifi-menu-test"
            )

        # Open New is list line 6 (Scan, Known Connected, Known Other, New
        # Strong, Secure New, Open New) and has no saved profile, so
        # selecting it connects straight away with no submenu and no
        # password.
        run_wifi_menu("6")
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "device wifi connect Open New ifname wlan0" in calls, (
            f"expected an open connect call, got: {calls}"
        )
        assert "password" not in calls, (
            f"an open network should not prompt for or send a password, got: {calls}"
        )

        # Secure New is list line 5 and must prompt for a passphrase (via
        # fuzzel --password) before connecting.
        run_wifi_menu("5", "TYPE:supersecret")
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "device wifi connect Secure New ifname wlan0 password supersecret" in calls, (
            f"expected a secure connect call with the typed passphrase, got: {calls}"
        )
        prompt_log = machine.succeed(f"cat {fuzzel_log}")
        assert "--password" in prompt_log, (
            f"expected the passphrase prompt to use --password, got: {prompt_log}"
        )

    with subtest("waybar-network-wifi-menu Settings opens nm-connection-editor with only Wi-Fi expanded"):
        machine.succeed("rm -f /tmp/nmcli-calls.log")
        machine.succeed("printf '%s\\n' 7 >/tmp/fuzzel-wifi-answers")
        machine.succeed(
            "FUZZEL_LOG=/tmp/fuzzel-wifi-menu.log FUZZEL_ANSWERS=/tmp/fuzzel-wifi-answers "
            "waybar-network-wifi-menu-test"
        )
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "nm-connection-editor -t 802-11-wireless -s" in calls, (
            f"expected the Wi-Fi-only settings call, got: {calls}"
        )

    with subtest(
        "waybar-network-wifi-menu polls device readiness after powering on the radio, not just device presence"
    ):
        # Regression test: nmcli lists a wifi device regardless of whether
        # the radio is powered, so a poll loop that only checks device
        # presence (an earlier version of this script did exactly that)
        # breaks after a single iteration -- it never actually waits for
        # the driver to come up. Exercises
        # waybar-network-wifi-menu-radio-poll-test (built from the same
        # source with a stateful nmcli stub -- see stubNmcliRadioPoll
        # above -- whose device-status STATE stays "unavailable" for the
        # first two calls, then reports ready).
        machine.succeed(
            "rm -f /tmp/nmcli-calls.log /tmp/radio-poll-on /tmp/radio-poll-status-calls"
        )
        machine.succeed("printf '%s\\n' CANCEL >/tmp/fuzzel-wifi-answers")
        machine.succeed(
            "FUZZEL_LOG=/tmp/fuzzel-wifi-menu.log FUZZEL_ANSWERS=/tmp/fuzzel-wifi-answers "
            "waybar-network-wifi-menu-radio-poll-test"
        )
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "radio wifi on" in calls, f"expected the radio to be powered on, got: {calls}"

        # The old, buggy poll loop broke after checking device status just
        # twice total (once before the radio check, once inside the loop --
        # both already non-empty on DEVICE regardless of STATE) -- the
        # fixed loop keeps polling until STATE itself is ready, which this
        # fixture doesn't happen until the third call.
        status_calls = calls.count("nmcli -t -f DEVICE,TYPE,STATE device status")
        assert status_calls >= 3, (
            f"expected the poll loop to check device status at least 3 times "
            f"(proving it waited on STATE, not just device presence), got "
            f"{status_calls} calls: {calls}"
        )

        # Only after readiness should the script proceed to scan and show
        # the (now-ready) network in the menu.
        fuzzel_log = machine.succeed("cat /tmp/fuzzel-wifi-menu.log")
        assert "Ready Network" in fuzzel_log, (
            f"expected the menu to reach the scan step and show the network, got: {fuzzel_log}"
        )

    with subtest(
        "waybar-network-ethernet reports a disabled state when NetworkManager is unavailable"
    ):
        out = machine.succeed("waybar-network-ethernet").strip()
        print(f"waybar-network-ethernet output: {out}")
        status = json.loads(out)
        assert status["class"] == "disabled", f"expected a disabled state, got: {out}"
        assert status["text"] == "󰈀", f"expected icon-only Ethernet text, got: {out}"

    with subtest(
        "waybar-network-ethernet-menu decodes escaped profile names and manages connections"
    ):
        # Exercises the real script (waybar-network-ethernet-menu-test, built
        # from the same source as waybar-network-ethernet-menu but with
        # nmcli/fuzzel replaced by stubs -- see stubNmcli/stubFuzzel above)
        # against fixture nmcli output, without a real NetworkManager or
        # Wayland compositor.
        fuzzel_log = "/tmp/fuzzel-menu.log"
        answers = "/tmp/fuzzel-answers"

        def run_menu(*choices):
            machine.succeed(f"rm -f {fuzzel_log} /tmp/nmcli-calls.log")
            machine.succeed(
                "printf '%s\\n' " + " ".join(choices) + f" >{answers}"
            )
            machine.succeed(
                f"FUZZEL_LOG={fuzzel_log} FUZZEL_ANSWERS={answers} "
                "waybar-network-ethernet-menu-test"
            )

        # Cancelling the very first prompt is enough to inspect the
        # top-level list: it must show profile names with nmcli's
        # colon/backslash escaping already undone, not the raw escaped form.
        run_menu("CANCEL")
        top_level = machine.succeed(f"cat {fuzzel_log}")
        assert "foo:bar" in top_level, f"expected decoded colon name, got: {top_level}"
        assert "back\\slash" in top_level, (
            f"expected decoded backslash name, got: {top_level}"
        )
        assert "a\\:b" in top_level, f"expected decoded mixed-escape name, got: {top_level}"
        assert "foo\\:bar" not in top_level, (
            f"colon escape should have been undone, got: {top_level}"
        )
        assert "back\\\\slash" not in top_level, (
            f"backslash escape should have been undone, got: {top_level}"
        )

        # Selecting the already-connected "Plain" profile (list line 1) then
        # "Disconnect" (submenu line 1, since it has a device) must resolve
        # back to the right uuid via the --index lookup, not just the label.
        run_menu("1", "1")
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "connection down uuid uuid-plain" in calls, f"expected disconnect call, got: {calls}"

        # Selecting a disconnected profile and choosing Connect uses the same
        # index-derived uuid path as Disconnect, but runs the opposite nmcli
        # action when the fixture has no active device.
        run_menu("2", "1")
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "connection up uuid uuid-colon" in calls, f"expected connect call, got: {calls}"

        # Back returns to the already-snapshotted top-level menu, where the
        # Settings item can still be selected.
        run_menu("2", "4", "6")
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "nm-connection-editor -t 802-3-ethernet -s" in calls, (
            f"expected settings call after Back, got: {calls}"
        )

        # Selecting the colon-escaped profile (list line 2), then Delete
        # (submenu line 3) and confirming Yes (confirm line 2) must delete
        # the uuid belonging to that profile, not a neighboring one --
        # exercising both the delete confirmation flow and that the index
        # lookup still lines up correctly for a profile with an escaped name.
        run_menu("2", "3", "2")
        calls = machine.succeed("cat /tmp/nmcli-calls.log")
        assert "connection delete uuid uuid-colon" in calls, f"expected delete call, got: {calls}"

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

    with subtest("waybar-audio-speaker reports volume level, mute, and disabled state"):
        # Exercises the real speaker-status.bash logic (waybar-audio-speaker-test,
        # built from the same source as waybar-audio-speaker but with pactl
        # replaced by stubPactl) against fixture pactl output, without a real
        # PipeWire/PulseAudio server.
        def sink_fixture(mute, volume_percent):
            return json.dumps(
                [
                    {
                        "name": "sink1",
                        "description": "Built-in Speakers",
                        "mute": mute,
                        "volume": {"front-left": {"value_percent": f"{volume_percent}%"}},
                    }
                ]
            )

        def speaker_status(default_sink, sinks_json):
            machine.succeed(f"printf '%s' {shlex.quote(default_sink)} >/tmp/default-sink")
            machine.succeed(f"printf '%s' {shlex.quote(sinks_json)} >/tmp/sinks.json")
            out = machine.succeed(
                "DEFAULT_SINK_FILE=/tmp/default-sink SINKS_JSON=/tmp/sinks.json "
                "waybar-audio-speaker-test"
            ).strip()
            return json.loads(out)

        status = speaker_status("sink1", sink_fixture(False, 80))
        assert status["class"] == "unmuted", f"expected unmuted, got: {status}"
        assert status["text"] == "󰕾", f"expected the high-volume icon, got: {status}"
        assert "80%" in status["tooltip"], f"expected volume in tooltip, got: {status}"

        status = speaker_status("sink1", sink_fixture(False, 20))
        assert status["text"] == "󰕿", f"expected the low-volume icon, got: {status}"

        status = speaker_status("sink1", sink_fixture(True, 80))
        assert status["class"] == "muted", f"expected muted, got: {status}"
        assert status["text"] == "󰝟", f"expected the muted icon, got: {status}"

        status = speaker_status("", "[]")
        assert status["class"] == "disabled", f"expected disabled, got: {status}"
        assert status["text"] == "󰝟", f"expected the muted-style icon for disabled, got: {status}"

    with subtest("waybar-audio-mic reports volume level, mute, and disabled state"):
        def source_fixture(mute, volume_percent):
            return json.dumps(
                [
                    {
                        "name": "source1",
                        "description": "Built-in Microphone",
                        "mute": mute,
                        "volume": {"front-left": {"value_percent": f"{volume_percent}%"}},
                        "monitor_source": "",
                    }
                ]
            )

        def mic_status(default_source, sources_json):
            machine.succeed(f"printf '%s' {shlex.quote(default_source)} >/tmp/default-source")
            machine.succeed(f"printf '%s' {shlex.quote(sources_json)} >/tmp/sources.json")
            out = machine.succeed(
                "DEFAULT_SOURCE_FILE=/tmp/default-source SOURCES_JSON=/tmp/sources.json "
                "waybar-audio-mic-test"
            ).strip()
            return json.loads(out)

        status = mic_status("source1", source_fixture(False, 80))
        assert status["class"] == "unmuted", f"expected unmuted, got: {status}"
        assert status["text"] == "󰍬", f"expected the microphone icon, got: {status}"
        assert "80%" in status["tooltip"], f"expected volume in tooltip, got: {status}"

        status = mic_status("source1", source_fixture(True, 80))
        assert status["class"] == "muted", f"expected muted, got: {status}"
        assert status["text"] == "󰍭", f"expected the muted-microphone icon (no dots), got: {status}"

        status = mic_status("", "[]")
        assert status["class"] == "disabled", f"expected disabled, got: {status}"
        assert status["text"] == "󰍭", f"expected the muted-style icon for disabled, got: {status}"

    with subtest("waybar-audio-speaker-menu switches the default sink and reroutes active streams"):
        # Exercises the real speaker-menu.bash logic (waybar-audio-speaker-menu-test,
        # built with pactl/fuzzel replaced by stubPactl/stubFuzzel) against
        # fixture pactl output and a scripted fuzzel selection.
        machine.succeed("rm -f /tmp/pactl-calls.log /tmp/fuzzel-menu.log")
        sinks = json.dumps(
            [
                {"name": "sink1", "description": "Speakers"},
                {"name": "sink2", "description": "Headphones"},
            ]
        )
        machine.succeed(f"printf '%s' {shlex.quote(sinks)} >/tmp/sinks.json")
        # One already-playing stream (sink-input index 42), currently on sink1.
        machine.succeed("printf '42\\tsink1\\t7\\t4294967295\\tfloat32le 2ch 48000Hz\\n' >/tmp/sink-inputs")
        machine.succeed("printf '2\\n' >/tmp/fuzzel-answers")

        machine.succeed(
            "FUZZEL_LOG=/tmp/fuzzel-menu.log FUZZEL_ANSWERS=/tmp/fuzzel-answers "
            "SINKS_JSON=/tmp/sinks.json SINK_INPUTS=/tmp/sink-inputs "
            "waybar-audio-speaker-menu-test"
        )

        fuzzel_log = machine.succeed("cat /tmp/fuzzel-menu.log")
        assert "Speakers" in fuzzel_log and "Headphones" in fuzzel_log, (
            f"expected both sink descriptions in the fuzzel menu, got: {fuzzel_log}"
        )

        calls = machine.succeed("cat /tmp/pactl-calls.log")
        assert "set-default-sink sink2" in calls, (
            f"expected the second (Headphones) sink to become default, got: {calls}"
        )
        assert "move-sink-input 42 sink2" in calls, (
            f"expected the active stream to be rerouted to the new default, got: {calls}"
        )

    with subtest("waybar-audio-mic-menu switches the default source, reroutes streams, and hides monitors"):
        machine.succeed("rm -f /tmp/pactl-calls.log /tmp/fuzzel-menu.log")
        sources = json.dumps(
            [
                {"name": "source1", "description": "Built-in Microphone", "monitor_source": ""},
                {"name": "source2", "description": "USB Headset Mic", "monitor_source": ""},
                # A sink's monitor -- must never appear as an input choice.
                {
                    "name": "sink1.monitor",
                    "description": "Monitor of Speakers",
                    "monitor_source": "sink1",
                },
            ]
        )
        machine.succeed(f"printf '%s' {shlex.quote(sources)} >/tmp/sources.json")
        machine.succeed("printf '9\\tsource1\\t3\\t4294967295\\tfloat32le 1ch 48000Hz\\n' >/tmp/source-outputs")
        machine.succeed("printf '2\\n' >/tmp/fuzzel-answers")

        machine.succeed(
            "FUZZEL_LOG=/tmp/fuzzel-menu.log FUZZEL_ANSWERS=/tmp/fuzzel-answers "
            "SOURCES_JSON=/tmp/sources.json SOURCE_OUTPUTS=/tmp/source-outputs "
            "waybar-audio-mic-menu-test"
        )

        fuzzel_log = machine.succeed("cat /tmp/fuzzel-menu.log")
        assert "Built-in Microphone" in fuzzel_log and "USB Headset Mic" in fuzzel_log, (
            f"expected both real input descriptions in the fuzzel menu, got: {fuzzel_log}"
        )
        assert "Monitor of Speakers" not in fuzzel_log, (
            f"a sink monitor should never be offered as an input, got: {fuzzel_log}"
        )

        calls = machine.succeed("cat /tmp/pactl-calls.log")
        assert "set-default-source source2" in calls, (
            f"expected the second (USB Headset Mic) source to become default, got: {calls}"
        )
        assert "move-source-output 9 source2" in calls, (
            f"expected the active recording to be rerouted to the new default, got: {calls}"
        )
  '';
}
