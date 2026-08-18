{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull.programs.sway) idle;
  cfg = config.thoughtfull.laptop;
  inherit (lib)
    concatMapStringsSep
    concatStringsSep
    groupBy
    head
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    optionalString
    sort
    toInt
    types
    ;
  inherit (pkgs) bash systemd;
  inherit (pkgs.thoughtfull) writeFileScriptBin;

  on-ac = writeFileScriptBin {
    name = "on-ac";
    replacements.bash = "${bash}/bin/bash";
    src = ./laptop/on-ac.bash;
  };
  onAc = "${on-ac}/bin/on-ac";

  docked = writeFileScriptBin {
    name = "docked";
    replacements.bash = "${bash}/bin/bash";
    src = ./laptop/docked.bash;
  };

  # Lid handling runs in the user session: sway sees the lid as a switch device,
  # so a bindswitch is the event source (logind's lid handling can only lock).
  # lid-suspend arms/fires the battery countdown; lid-switch is the bindswitch
  # handler; lid-power-watch re-arms on AC changes (the bindswitch can't see them).
  lid-suspend = writeFileScriptBin {
    name = "lid-suspend";
    replacements = {
      bash = "${bash}/bin/bash";
      docked = "${docked}/bin/docked";
      on-ac = onAc;
    };
    src = ./laptop/lid-suspend.bash;
  };
  lid-switch = writeFileScriptBin {
    name = "lid-switch";
    replacements = {
      bash = "${bash}/bin/bash";
      docked = "${docked}/bin/docked";
      lid-suspend = "${lid-suspend}/bin/lid-suspend";
    };
    src = ./laptop/lid-switch.bash;
  };
  lid-power-watch = writeFileScriptBin {
    name = "lid-power-watch";
    replacements = {
      bash = "${bash}/bin/bash";
      lid-suspend = "${lid-suspend}/bin/lid-suspend";
      udevadm = "${systemd}/bin/udevadm";
    };
    src = ./laptop/lid-power-watch.bash;
  };

  # The single "sleep" seam: issue #295 switches this to
  # `systemctl suspend-then-hibernate` once hibernate is set up.
  sleepCommand = "systemctl suspend";

  blank = ''swaymsg "output * power off"'';
  unblank = ''swaymsg "output * power on"'';

  # Idle timeline as power-guarded events, decided at fire time: `on-ac || cmd`
  # runs cmd only on battery, `on-ac && cmd` only on AC. Events that land on the
  # same timeout (by default the AC lock and the battery suspend both at 15m) are
  # merged into a single `timeout` line, so equal durations never collide and
  # distinct ones (e.g. a longer batterySleepSeconds) split cleanly.
  events = [
    {
      at = cfg.batteryLockSeconds;
      run = "${onAc} || loginctl lock-session";
    }
    {
      at = cfg.batteryLockSeconds + cfg.batteryBlankDelaySeconds;
      run = "${onAc} || ${blank}";
      resume = unblank;
    }
    {
      at = idle.lockSeconds;
      run = "${onAc} && loginctl lock-session";
    }
    {
      at = cfg.batterySleepSeconds;
      run = "${onAc} || ${sleepCommand}";
    }
    {
      at = idle.lockSeconds + idle.blankDelaySeconds;
      run = "${onAc} && ${blank}";
      resume = unblank;
    }
  ];
  byAt = groupBy (e: toString e.at) events;
  timeoutLine =
    at:
    let
      group = byAt.${at};
      runs = concatMapStringsSep "; " (e: e.run) group;
      resumes = builtins.filter (e: e ? resume) group;
      resumeStr = optionalString (resumes != [ ]) " resume '${(head resumes).resume}'";
    in
    "timeout ${at} '${runs}'${resumeStr}";
  sortedAts = sort (a: b: toInt a < toInt b) (builtins.attrNames byAt);
  # No `before-sleep`: systemd-lock-handler locks before sleep synchronously via
  # sleep.target Requires=lock.target; a swayidle before-sleep would race it.
  idleConfig = concatStringsSep "\n" (map timeoutLine sortedAts) + "\n";
in
{
  config = mkIf cfg.enable {
    # Closing the lid locks the session rather than suspending (on AC or
    # battery), and is ignored when docked. logind's "lock" action only emits the
    # Lock signal; nixosModules/gtklock.nix turns that into an actual lock screen
    # via lock.target -- the same path loginctl/power-menu/waybar/swayidle use.
    services.logind.settings.Login = {
      HandleLidSwitch = mkDefault "lock";
      HandleLidSwitchExternalPower = mkDefault "lock";
      HandleLidSwitchDocked = mkDefault "ignore";
    };

    # Replace sway/idle.nix's default (mkDefault) config with the power-aware
    # one: shorter timings and a suspend on battery, the plain AC timings on AC.
    programs.swayidle.extraConfig = idleConfig;

    # Closing the lid while docked disables the internal panel so everything moves
    # to the external monitor -- the hardware probe confirmed eDP-1 stays
    # DRM-connected on lid close, so kanshi can't do this itself. Otherwise the
    # bindswitch arms the battery suspend countdown. --locked so it still fires
    # while the lock screen (from logind's lid lock) is up.
    environment.etc."sway/config.d/laptop-lid.conf".text = ''
      bindswitch --locked --no-warn lid:on exec ${lid-switch}/bin/lid-switch on
      bindswitch --locked --no-warn lid:off exec ${lid-switch}/bin/lid-switch off
    '';

    systemd.user = {
      services.lid-suspend = {
        description = "Suspend after the lid has stayed closed on battery";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lid-suspend}/bin/lid-suspend fire";
        };
      };
      # Started on demand by `lid-suspend arm` (from the bindswitch and the power
      # watcher), not wanted by any target -- so it only counts down while the lid
      # is actually closed on battery.
      timers.lid-suspend = {
        description = "Countdown to suspend after the lid closes on battery";
        timerConfig.OnActiveSec = "${toString cfg.lidSuspendSeconds}s";
      };
      services.lid-power-watch = {
        description = "Re-arm the lid suspend countdown when AC power changes";
        after = [ "sway-session.target" ];
        bindsTo = [ "sway-session.target" ];
        wantedBy = [ "sway-session.target" ];
        serviceConfig = {
          ExecStart = "${lid-power-watch}/bin/lid-power-watch";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };
    };
  };

  options.thoughtfull.laptop = {
    enable = mkEnableOption ''
      laptop power management: lock immediately when the lid closes (ignored when
      docked), and power-aware idle -- shorter lock/blank timings plus suspend on
      battery, the plain AC timings on AC
    '';
    batteryLockSeconds = mkOption {
      default = 300;
      description = "On battery, seconds of inactivity before the screen locks (default 5 minutes).";
      type = types.ints.positive;
    };
    batteryBlankDelaySeconds = mkOption {
      default = 300;
      description = "On battery, seconds after locking before the outputs power off (default 5 minutes).";
      type = types.ints.positive;
    };
    batterySleepSeconds = mkOption {
      default = 900;
      description = ''
        On battery, seconds of inactivity before the system suspends (default 15
        minutes). Independent of the AC lock time
        (thoughtfull.programs.sway.idle.lockSeconds).
      '';
      type = types.ints.positive;
    };
    lidSuspendSeconds = mkOption {
      default = 900;
      description = ''
        On battery, seconds after the lid closes before the system suspends
        (default 15 minutes). Cancelled if AC is plugged in, the machine is
        docked, or the lid reopens.
      '';
      type = types.ints.positive;
    };
  };
}
