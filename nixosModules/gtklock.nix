{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) gnupg;
  cfg = config.programs.gtklock;
  inherit (lib) mkDefault mkIf;
  inherit (pkgs)
    bash
    gtklock
    mako
    systemd
    ;
  inherit (pkgs.thoughtfull) theme-toggle writeFileScriptBin;
  clear-secrets = writeFileScriptBin {
    name = "clear-secrets";
    replacements = {
      bash = "${bash}/bin/bash";
      gpgconf = "${gnupg.package}/bin/gpgconf";
    };
    src = ./gtklock/clear-secrets.bash;
  };
  # gtklock's lock-command: signals systemd (Type=notify below) that the screen
  # is actually locked, then clears cached credentials.
  on-lock = writeFileScriptBin {
    name = "on-lock";
    replacements = {
      bash = "${bash}/bin/bash";
      clear-secrets = "${clear-secrets}/bin/clear-secrets";
      systemd-notify = "${systemd}/bin/systemd-notify";
    };
    src = ./gtklock/on-lock.bash;
  };
  gtklock-wrapper = writeFileScriptBin {
    name = "gtklock";
    replacements = {
      bash = "${bash}/bin/bash";
      gtklock = "${gtklock}/bin/gtklock";
      makoctl = "${mako}/bin/makoctl";
      theme-get = "${theme-toggle}/bin/theme-get";
    };
    src = ./gtklock/wrapper.bash;
  };
in
{
  environment.systemPackages = [ clear-secrets ];
  programs.gtklock = {
    package = mkDefault gtklock-wrapper;
    config.main = {
      idle-hide = mkDefault true;
      idle-timeout = mkDefault 60;
      lock-command = mkDefault "${on-lock}/bin/on-lock";
      start-hidden = mkDefault true;
    };
    modules = with pkgs; [
      gtklock-powerbar-module
      gtklock-userinfo-module
    ];
  };

  # Make logind's Lock D-Bus signal -- what `loginctl lock-session` sends, and
  # also what HandleLidSwitch(ExternalPower)=lock in nixosModules/laptop.nix
  # triggers -- actually show the lock screen. systemd-lock-handler bridges that
  # signal to lock.target, which the user service below hooks into.
  services.systemd-lock-handler.enable = mkIf cfg.enable (mkDefault true);
  systemd.user.services.gtklock-session-lock = mkIf cfg.enable {
    description = "Lock the screen for lock.target (loginctl lock-session, lid closed, ...)";
    # gtklock needs the Wayland session up (same environment as the idle-timeout
    # locks in sway/idle.nix).
    after = [ "sway-session.target" ];
    bindsTo = [ "sway-session.target" ];
    # partOf (not bindsTo) to lock.target: follow it down if something else stops
    # it, but a lone `systemctl --user restart` of this service must never pull
    # lock.target up if it isn't already active.
    partOf = [ "lock.target" ];
    wantedBy = [ "lock.target" ];
    # lock.target and unlock.target ship as a Conflicts= pair (starting one stops
    # the other), which is what lets lock.target re-arm for the next lock.
    # Reporting success here on exit (gtklock unlocked normally) starts
    # unlock.target so the toggle flips back. Without this, lock.target would
    # stay active forever after the first unlock and a second lock request would
    # find it already "active" -- a no-op that never re-runs this service.
    onSuccess = [ "unlock.target" ];
    serviceConfig = {
      # Type=notify: gtklock's lock-command (on-lock) sends `systemd-notify
      # --ready` the moment the screen actually locks, so lock.target -- and
      # sleep.target before a suspend -- are only "reached" once locked, not when
      # gtklock merely forked. Without this the machine suspends before gtklock
      # paints and flashes the unlocked screen on resume. NotifyAccess=all because
      # the notifier (on-lock) is a grandchild of the unit's main process (the
      # wrapper), not the main process itself.
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = mkDefault "${cfg.package}/bin/gtklock";
    };
  };
}
