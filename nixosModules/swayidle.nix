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
  inherit (pkgs) systemd writeText;
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
      # systemd is for loginctl -- extraConfig's lock triggers run `loginctl
      # lock-session` (see sway/idle.nix) rather than invoking gtklock
      # directly, so they arm nixosModules/gtklock.nix's lock.target wiring.
      path = [
        sway.package
        systemd
      ];
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
