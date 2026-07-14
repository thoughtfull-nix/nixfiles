{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (lib) mkIf;
  inherit (pkgs)
    kanshi
    wdisplays
    ;
  inherit (pkgs.thoughtfull) waybar-displays;
in
{
  environment = mkIf sway.enable {
    etc."xdg/kanshi/config".source = ./kanshi/config;
    systemPackages = [
      kanshi
      wdisplays
    ];
  };
  systemd.user.services.kanshi = mkIf sway.enable {
    after = [ "sway-session.target" ];
    bindsTo = [ "sway-session.target" ];
    wantedBy = [ "sway-session.target" ];
    # kanshi-active (invoked from profile `exec` directives) records the active
    # profile and signals Waybar.
    path = [ waybar-displays ];
    serviceConfig = {
      ExecStart = "${kanshi}/bin/kanshi --config /etc/xdg/kanshi/config";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };
}
