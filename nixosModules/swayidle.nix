{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway swayidle;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  inherit (pkgs) writeText;
  configFile = writeText "config" swayidle.extraConfig;
in
{
  config = {
    environment.systemPackages = mkIf swayidle.enable [ swayidle.package ];
    systemd.user.services.swayidle = mkIf swayidle.enable {
      after = [ "sway-session.target" ];
      bindsTo = [ "sway-session.target" ];
      description = mkDefault "Idle monitoring for sway";
      enable = mkDefault swayidle.enable;
      path = [ sway.package ];
      serviceConfig.ExecStart = mkDefault "${swayidle.package}/bin/swayidle -w -C ${configFile}";
      wantedBy = [ "sway-session.target" ];
    };
  };
  options.programs.swayidle = {
    enable = mkEnableOption "swayidle" // {
      default = sway.enable;
    };
    extraConfig = mkOption {
      type = types.str;
    };
    package = mkOption {
      default = pkgs.swayidle;
      type = types.package;
    };
  };
}
