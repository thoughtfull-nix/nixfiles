{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (config.thoughtfull) graphical;
  inherit (config.thoughtfull.programs) slack;
  inherit (lib) mkDefault mkEnableOption mkIf;
  inherit (pkgs) bash;
  inherit (pkgs.thoughtfull) writeFileScript;
  login = writeFileScript {
    name = "slack-login";
    replacements = {
      bash = "${bash}/bin/bash";
      slack = "${pkgs.slack}/bin/slack";
      swaymsg = "${sway.package}/bin/swaymsg";
    };
    src = ./slack/login.bash;
  };
in
{
  config = {
    environment.systemPackages = mkIf slack.enable [ pkgs.slack ];
    thoughtfull.impermanence.user.directories = mkIf slack.enable [
      {
        directory = ".config/Slack";
        mode = "0700";
      }
    ];
    systemd.user.services.slack-login = {
      description = "Launch slack on workspace 4 at login";
      after = [
        "sway-session.target"
        "waybar.service"
      ];
      # See gtk-defaults in sway.nix for why partOf (follow sway-session
      # down) rather than bindsTo (would also pull sway-session.target up on
      # a lone `systemctl --user start slack-login.service`, which isn't
      # wanted here).
      partOf = [ "sway-session.target" ];
      enable = mkDefault (sway.enable && slack.enable);
      wantedBy = [ "sway-session.target" ];
      # A rebuild-switch that touches this unit's closure (e.g. a slack/sway
      # package bump) shouldn't relaunch slack mid-session.
      restartIfChanged = mkDefault false;
      serviceConfig = {
        Type = "oneshot";
        # See foot-login in foot.nix for why oneshot + RemainAfterExit, and
        # for KillMode=process, here.
        RemainAfterExit = true;
        KillMode = "process";
        ExecStart = "${login}";
      };
    };
  };
  options.thoughtfull.programs.slack.enable = mkEnableOption "slack" // {
    default = graphical.enable;
  };
}
