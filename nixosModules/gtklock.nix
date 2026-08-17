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
    util-linux
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
  gtklock-wrapper = writeFileScriptBin {
    name = "gtklock";
    replacements = {
      bash = "${bash}/bin/bash";
      flock = "${util-linux}/bin/flock";
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
      lock-command = mkDefault "${clear-secrets}/bin/clear-secrets";
      start-hidden = mkDefault true;
    };
    modules = with pkgs; [
      gtklock-powerbar-module
      gtklock-userinfo-module
    ];
  };

  # Make logind's Lock D-Bus signal -- what `loginctl lock-session` sends,
  # and also what HandleLidSwitch(ExternalPower)=lock in
  # nixosModules/laptop.nix triggers -- actually show the lock screen.
  # systemd-lock-handler bridges that signal to lock.target, which the user
  # service below hooks into.
  services.systemd-lock-handler.enable = mkIf cfg.enable (mkDefault true);
  systemd.user.services.gtklock-session-lock = mkIf cfg.enable {
    description = "Lock the screen for lock.target (loginctl lock-session, lid closed, ...)";
    # Same environment gtklock already runs in for idle-timeout/before-sleep
    # locks (see sway/idle.nix) -- gtklock needs the Wayland session up.
    after = [ "sway-session.target" ];
    bindsTo = [ "sway-session.target" ];
    # partOf (not bindsTo) to lock.target: follow it down if something else
    # stops it, but a lone `systemctl --user restart` of this service must
    # never pull lock.target up if it isn't already active.
    partOf = [ "lock.target" ];
    wantedBy = [ "lock.target" ];
    # lock.target and unlock.target ship as a Conflicts= pair (starting one
    # stops the other), which is what lets lock.target re-arm for the next
    # lock. Reporting success here on exit (i.e. gtklock unlocked normally)
    # starts unlock.target, so that toggle actually flips back. Without
    # this, lock.target would stay active forever after the first unlock
    # and a second lock request would find it already "active" -- a no-op
    # that never re-runs this service.
    onSuccess = [ "unlock.target" ];
    serviceConfig.ExecStart = mkDefault "${cfg.package}/bin/gtklock";
  };
}
