# Checks for nixosModules/laptop.nix (thoughtfull.laptop.enable):
#
#   - Closing the lid locks immediately on AC or battery, and is ignored when
#     docked -- via logind's HandleLidSwitch* (the "lock" action reaches the
#     screen through nixosModules/gtklock.nix's lock.target, tests/gtklock.nix).
#   - Idle becomes power-aware: on battery lock @5m / blank @10m / suspend @15m;
#     on AC (and desktops, which don't enable this) lock @15m / blank @20m, never
#     suspend. Implemented with fire-time `on-ac` checks in the swayidle config.
#   - The `on-ac` helper's actual bash logic is exercised against a faked /sys.
#
# The lid-close *delayed* suspend on battery and its lid/AC event source need
# real hardware and are handled separately.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  pkgs = nixpkgs.extend self.overlays.thoughtfull;

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
        ../nixosModules/swayidle.nix
        ../nixosModules/sway/idle.nix
        ../nixosModules/laptop.nix
        { programs.sway.enable = true; }
        extraModule
      ];
    };

  disabled = mkEval { };
  enabled = mkEval { thoughtfull.laptop.enable = true; };

  disabledIdle = disabled.config.programs.swayidle.extraConfig;
  enabledIdle = enabled.config.programs.swayidle.extraConfig;

  # batterySleepSeconds defaults to 900, the same as the AC lock time
  # (idle.lockSeconds), so the two share one 15m `timeout`. Bumping it proves the
  # two are independently configurable and split into separate timeout lines.
  splitIdle =
    (mkEval {
      thoughtfull.laptop.enable = true;
      thoughtfull.laptop.batterySleepSeconds = 1500;
    }).config.programs.swayidle.extraConfig;
  disabledLogin = disabled.config.services.logind.settings.Login or { };
  enabledLogin = enabled.config.services.logind.settings.Login;

  has = needle: haystack: lib.hasInfix needle haystack;

  # Rebuild the helpers from the same source the module uses, to exercise their
  # logic against faked /sys and a stub systemctl.
  onAc = pkgs.thoughtfull.writeFileScriptBin {
    name = "on-ac";
    replacements.bash = "${pkgs.bash}/bin/bash";
    src = ../nixosModules/laptop/on-ac.bash;
  };
  docked = pkgs.thoughtfull.writeFileScriptBin {
    name = "docked";
    replacements.bash = "${pkgs.bash}/bin/bash";
    src = ../nixosModules/laptop/docked.bash;
  };
  lidSuspend = pkgs.thoughtfull.writeFileScriptBin {
    name = "lid-suspend";
    replacements = {
      bash = "${pkgs.bash}/bin/bash";
      docked = "${docked}/bin/docked";
      on-ac = "${onAc}/bin/on-ac";
    };
    src = ../nixosModules/laptop/lid-suspend.bash;
  };
  # lid-switch calls docked + swaymsg/loginctl (stubbed in the runCommand) and
  # lid-suspend (stubbed to a no-op here; its own logic is covered above).
  lidSuspendStub = pkgs.writeShellScriptBin "lid-suspend" "exit 0";
  lidSwitch = pkgs.thoughtfull.writeFileScriptBin {
    name = "lid-switch";
    replacements = {
      bash = "${pkgs.bash}/bin/bash";
      docked = "${docked}/bin/docked";
      lid-suspend = "${lidSuspendStub}/bin/lid-suspend";
    };
    src = ../nixosModules/laptop/lid-switch.bash;
  };

  checks = [
    # ---- logind lid handling ----
    {
      name = "disabled: lid-switch handling is left untouched";
      ok = !(disabledLogin ? HandleLidSwitch) && !(disabledLogin ? HandleLidSwitchExternalPower);
    }
    {
      name = "enabled: closing the lid locks (not suspends) on battery and on AC";
      ok = enabledLogin.HandleLidSwitch == "lock" && enabledLogin.HandleLidSwitchExternalPower == "lock";
    }
    {
      name = "enabled: closing the lid while docked is ignored";
      ok = enabledLogin.HandleLidSwitchDocked == "ignore";
    }

    # ---- idle policy: disabled keeps the plain AC/desktop config ----
    {
      name = "disabled: idle is the default AC config (lock @15m, no battery timings, no suspend)";
      ok =
        has "timeout 900 'loginctl lock-session'" disabledIdle
        && !(has "timeout 300 " disabledIdle)
        && !(has "systemctl suspend" disabledIdle);
    }

    # ---- idle policy: enabled becomes power-aware ----
    {
      name = "enabled: on battery, locks after 5 minutes";
      ok = has "timeout 300 " enabledIdle && has "|| loginctl lock-session" enabledIdle;
    }
    {
      name = "enabled: on battery, blanks after 10 minutes";
      ok = has "timeout 600 " enabledIdle;
    }
    {
      name = "enabled: at 15 minutes, AC locks and battery suspends (merged, both default to 900)";
      ok =
        has "timeout 900 " enabledIdle
        && has "&& loginctl lock-session" enabledIdle
        && has "|| systemctl suspend" enabledIdle;
    }
    {
      name = "enabled: on AC, blanks after 20 minutes";
      ok = has "timeout 1200 " enabledIdle;
    }
    {
      name = "battery sleep time is configurable independently of the AC lock time";
      ok =
        has "timeout 1500 " splitIdle
        && has "|| systemctl suspend" splitIdle
        && !(has "timeout 1500 " enabledIdle);
    }
    {
      name = "enabled: locks go through loginctl (never gtklock), no racy before-sleep";
      ok =
        has "loginctl lock-session" enabledIdle
        && !(has "gtklock" enabledIdle)
        && !(has "before-sleep" enabledIdle);
    }

    # ---- lid bindswitch + suspend countdown units ----
    {
      name = "enabled: a bindswitch runs the lid handler on close and open";
      ok =
        let
          conf = enabled.config.environment.etc."sway/config.d/laptop-lid.conf".text;
        in
        has "bindswitch --locked --no-warn lid:on exec" conf
        && has "/bin/lid-switch on" conf
        && has "/bin/lid-switch off" conf;
    }
    {
      name = "enabled: the lid-suspend timer/service and AC power watcher exist";
      ok =
        (enabled.config.systemd.user.timers ? lid-suspend)
        && (enabled.config.systemd.user.services ? lid-suspend)
        && (enabled.config.systemd.user.services ? lid-power-watch);
    }
    {
      name = "disabled: no lid bindswitch or suspend units";
      ok =
        !(disabled.config.environment.etc ? "sway/config.d/laptop-lid.conf")
        && !(disabled.config.systemd.user.timers ? lid-suspend);
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    laptop test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  pkgs.runCommand "laptop-test" { } ''
    set -eu
    fail() { echo "laptop script test failed: $1" >&2; exit 1; }

    # --- on-ac: a Mains supply online means AC ---
    mkdir -p ac/AC0 batt/AC0 batt/BAT0 none
    printf 'Mains\n'   >ac/AC0/type;   printf '1\n'   >ac/AC0/online
    printf 'Mains\n'   >batt/AC0/type; printf '0\n'   >batt/AC0/online
    printf 'Battery\n' >batt/BAT0/type

    POWER_SUPPLY_ROOT=$PWD/ac   ${onAc}/bin/on-ac || fail "on-ac should exit 0 on AC"
    POWER_SUPPLY_ROOT=$PWD/batt ${onAc}/bin/on-ac && fail "on-ac should exit non-zero on battery" || true
    POWER_SUPPLY_ROOT=$PWD/none ${onAc}/bin/on-ac && fail "on-ac should exit non-zero with no adapter" || true

    # --- docked: any non-eDP DRM connector connected ---
    mkdir -p drmdock/card1-eDP-1 drmdock/card1-HDMI-A-1 drmsolo/card1-eDP-1
    printf 'connected\n' >drmdock/card1-eDP-1/status
    printf 'connected\n' >drmdock/card1-HDMI-A-1/status
    printf 'connected\n' >drmsolo/card1-eDP-1/status
    DRM_ROOT=$PWD/drmdock ${docked}/bin/docked || fail "docked should be true with an external connected"
    DRM_ROOT=$PWD/drmsolo ${docked}/bin/docked && fail "docked should be false with only eDP" || true

    # --- lid-suspend fire: suspends only when lid closed AND battery AND not docked ---
    printf 'state:      closed\n' >lid-closed
    printf 'state:      open\n'   >lid-open
    mkdir -p stub
    printf '#!/bin/sh\necho "$*" >>"$SUSLOG"\n' >stub/systemctl
    chmod +x stub/systemctl
    export SUSLOG=$PWD/systemctl.log

    fire() { : >"$SUSLOG"; PATH=$PWD/stub:$PATH POWER_SUPPLY_ROOT="$1" DRM_ROOT="$2" LID_STATE_GLOB="$3" ${lidSuspend}/bin/lid-suspend fire; }

    fire "$PWD/batt" "$PWD/drmsolo" "$PWD/lid-closed"
    grep -q suspend "$SUSLOG" || fail "should suspend when lid closed, on battery, not docked"
    fire "$PWD/ac"   "$PWD/drmsolo" "$PWD/lid-closed"; ! grep -q suspend "$SUSLOG" || fail "must not suspend on AC"
    fire "$PWD/batt" "$PWD/drmdock" "$PWD/lid-closed"; ! grep -q suspend "$SUSLOG" || fail "must not suspend when docked"
    fire "$PWD/batt" "$PWD/drmsolo" "$PWD/lid-open";   ! grep -q suspend "$SUSLOG" || fail "must not suspend when lid open"

    # --- lid-switch on: docked switches to the external (no lock); undocked locks
    # (locking here, not just via logind, is what survives logind's post-resume
    # lid holdoff) ---
    mkdir -p actstub
    printf '#!/bin/sh\necho "swaymsg $*" >>"$ACTLOG"\n'  >actstub/swaymsg
    printf '#!/bin/sh\necho "loginctl $*" >>"$ACTLOG"\n' >actstub/loginctl
    chmod +x actstub/swaymsg actstub/loginctl
    export ACTLOG=$PWD/actions.log
    swon() { : >"$ACTLOG"; PATH=$PWD/actstub:$PATH DRM_ROOT="$1" ${lidSwitch}/bin/lid-switch on; }

    swon "$PWD/drmdock"
    grep -q 'swaymsg output eDP-1 disable' "$ACTLOG" || fail "docked lid close should switch to the external (disable eDP-1)"
    ! grep -q loginctl "$ACTLOG" || fail "docked lid close must not lock"
    swon "$PWD/drmsolo"
    grep -q 'loginctl lock-session' "$ACTLOG" || fail "undocked lid close should lock"
    ! grep -q 'eDP-1 disable' "$ACTLOG" || fail "undocked lid close must not disable eDP-1"

    touch $out
  ''
