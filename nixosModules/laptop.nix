{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) gtklock;
  inherit (config.thoughtfull) laptop;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    ;
  inherit (pkgs) systemd;
in
{
  config = mkIf laptop.enable {
    # The hard requirement: closing the lid must never suspend the machine,
    # on AC or on battery, so long-running work (builds, downloads, etc.)
    # keeps going unattended. "lock" locks the session instead, without
    # touching power state at all. This alone satisfies that requirement even
    # if nothing below ends up wired up (e.g. gtklock disabled) -- everything
    # past this point is about suspending later if the lock goes unanswered
    # on battery. Making "lock" actually show the lock screen is
    # nixosModules/gtklock.nix's job (systemd-lock-handler + lock.target),
    # shared with `loginctl lock-session` and anything else that emits
    # logind's Lock signal.
    services.logind.settings.Login = {
      HandleLidSwitch = mkDefault "lock";
      HandleLidSwitchExternalPower = mkDefault "lock";
    };

    # logind's Lock signal doesn't say *why* the session locked, so this
    # starts from any lock while on battery -- idle-timeout, a manual lock,
    # or a lid-close alike -- not exclusively from closing the lid. Only
    # useful with gtklock enabled (nothing else drives lock.target).
    systemd.user.timers.battery-lock-suspend = mkIf gtklock.enable {
      description = "Suspend if still locked on battery power after timeout";
      partOf = [ "lock.target" ];
      wantedBy = [ "lock.target" ];
      timerConfig.OnActiveSec = mkDefault "10min";
    };
    systemd.user.services.battery-lock-suspend = mkIf gtklock.enable {
      description = "Suspend if still locked on battery power";
      # ConditionACPower is re-evaluated when the timer above fires, not
      # snapshotted when the timer started -- so plugging in before it fires
      # cancels the pending suspend for free, and this is a no-op if the lid
      # closed on AC power to begin with.
      unitConfig.ConditionACPower = mkDefault false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = mkDefault "${systemd}/bin/systemctl suspend";
      };
    };
  };

  options.thoughtfull.laptop.enable = mkEnableOption ''
    laptop-specific power management: lock the screen immediately when the
    lid closes (AC or battery), but only suspend after staying locked for a
    while on battery power (see battery-lock-suspend.timer's OnActiveSec) --
    stay awake indefinitely on AC
  '';
}
