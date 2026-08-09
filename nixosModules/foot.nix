{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault;
  inherit (pkgs) bash foot;
  inherit (pkgs.thoughtfull) theme-toggle writeFileScript writeFileScriptBin;
  cfg = config.programs.foot;
  footWrapper = writeFileScriptBin {
    name = "foot";
    replacements = {
      bash = "${bash}/bin/bash";
      foot = "${foot}/bin/foot";
      theme-get = "${theme-toggle}/bin/theme-get";
    };
    src = ./foot/wrapper.bash;
  };
  login = writeFileScript {
    name = "foot-login";
    replacements = {
      bash = "${bash}/bin/bash";
      foot = "${cfg.package}/bin/foot";
      swaymsg = "${sway.package}/bin/swaymsg";
    };
    src = ./foot/login.bash;
  };
in
{
  programs.foot = {
    enable = mkDefault graphical.enable;
    package = mkDefault footWrapper;
    settings = {
      main.font = mkDefault "FiraCode Nerd Font:size=11";
      # Adwaita light theme (applied via SIGUSR1 signal for runtime switching)
      colors-dark = {
        background = mkDefault "ffffff";
        foreground = mkDefault "1e1e1e";
        regular0 = mkDefault "1e1e1e";
        regular1 = mkDefault "c01c28";
        regular2 = mkDefault "26a269";
        regular3 = mkDefault "a2734c";
        regular4 = mkDefault "12488b";
        regular5 = mkDefault "a347ba";
        regular6 = mkDefault "2aa1b3";
        regular7 = mkDefault "d0cfcc";
        bright0 = mkDefault "5e5c64";
        bright1 = mkDefault "f66151";
        bright2 = mkDefault "33d17a";
        bright3 = mkDefault "e9ad0c";
        bright4 = mkDefault "2a7bde";
        bright5 = mkDefault "c061cb";
        bright6 = mkDefault "33c7de";
        bright7 = mkDefault "ffffff";
      };
      # Adwaita dark theme (applied via SIGUSR2 signal for runtime switching)
      colors-light = {
        background = mkDefault "1e1e1e";
        foreground = mkDefault "ffffff";
        regular0 = mkDefault "1e1e1e";
        regular1 = mkDefault "c01c28";
        regular2 = mkDefault "26a269";
        regular3 = mkDefault "a2734c";
        regular4 = mkDefault "12488b";
        regular5 = mkDefault "a347ba";
        regular6 = mkDefault "2aa1b3";
        regular7 = mkDefault "d0cfcc";
        bright0 = mkDefault "5e5c64";
        bright1 = mkDefault "f66151";
        bright2 = mkDefault "33d17a";
        bright3 = mkDefault "e9ad0c";
        bright4 = mkDefault "2a7bde";
        bright5 = mkDefault "c061cb";
        bright6 = mkDefault "33c7de";
        bright7 = mkDefault "ffffff";
      };
    };
  };
  systemd.user.services.foot-login = {
    description = "Launch foot on workspace 1 at login";
    after = [
      "sway-session.target"
      "waybar.service"
    ];
    # See gtk-defaults in sway.nix for why partOf (follow sway-session down)
    # rather than bindsTo (would also pull sway-session.target up on a lone
    # `systemctl --user start foot-login.service`, which isn't wanted here).
    partOf = [ "sway-session.target" ];
    enable = mkDefault (sway.enable && cfg.enable);
    wantedBy = [ "sway-session.target" ];
    # A rebuild-switch that touches this unit's closure (e.g. a foot/sway
    # package bump) shouldn't relaunch foot mid-session.
    restartIfChanged = mkDefault false;
    serviceConfig = {
      Type = "oneshot";
      # Type=oneshot means quitting foot later can't retroactively fail this
      # unit -- its result is fixed the moment login.bash's `swaymsg` call
      # returns. RemainAfterExit keeps it showing active/exited rather than
      # inactive (dead) once that's happened, same reasoning as gtk-defaults.
      RemainAfterExit = true;
      # login.bash backgrounds foot and exits, so the actual foot process
      # stays in this unit's control group after ExecStart returns.
      # KillMode's default (control-group) would mean any stop of this unit
      # -- including partOf's propagation from `systemctl --user stop
      # sway-session.target` on every sway exit, or just a manual
      # `systemctl --user restart foot-login.service` -- kills that already
      # running foot window, not just (the long-since-exited) launcher
      # script. KillMode=process only signals the tracked main process,
      # which for a oneshot is gone by the time anyone stops the unit, so
      # this reaches nothing.
      KillMode = "process";
      ExecStart = "${login}";
    };
  };
}
