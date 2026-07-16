{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  cfg = config.thoughtfull.programs.sway.kanshi;
  inherit (lib) mkIf mkOption types;
  inherit (pkgs)
    kanshi
    wdisplays
    ;
  inherit (pkgs.thoughtfull) waybar-displays;
  enabled = sway.enable && cfg.configFile != null;
in
{
  config = {
    environment = mkIf sway.enable {
      etc."xdg/kanshi/config" = mkIf enabled { source = cfg.configFile; };
      systemPackages = [
        kanshi
        wdisplays
      ];
    };
    systemd.user.services.kanshi = mkIf enabled {
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
  };
  options.thoughtfull.programs.sway.kanshi.configFile = mkOption {
    default = null;
    description = ''
      Path to this host's kanshi output-profile config. Output profiles are
      hardware-specific (monitor identifiers, positions, modes), so each host
      that enables sway should set its own, for example `./kanshi/config` next
      to its `nixosConfigurations/<host>.nix`.
    '';
    type = types.nullOr types.path;
  };
}
