{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) gtklock sway;
  inherit (lib) mkDefault mkIf;
  inherit (pkgs)
    bash
    curl
    font-awesome
    networkmanagerapplet
    pasystray
    waybar
    ;
  inherit (pkgs.thoughtfull) theme-toggle waybar-yubikey;
  power-menu = pkgs.thoughtfull.power-menu.override { gtklock = gtklock.package; };
  cfg = config.programs.waybar;
in
{
  environment = lib.mkIf sway.enable {
    etc = {
      "xdg/waybar/config.jsonc".source = ./waybar/config.jsonc;
      "xdg/waybar/style.css".source = ./waybar/style.css;
    };
    systemPackages = [
      font-awesome
      networkmanagerapplet
      pasystray
      power-menu
      waybar
      waybar-yubikey
    ];
  };
  programs = {
    nm-applet.enable = mkDefault sway.enable;
    waybar = {
      enable = mkDefault sway.enable;
      systemd.target = mkDefault "sway-session.target";
    };
    yubikey-touch-detector = {
      enable = mkDefault sway.enable;
      libnotify = mkDefault false;
      verbose = mkDefault true;
    };
  };
  systemd.user.services = mkIf cfg.enable {
    pasystray = {
      after = [ "sway-session.target" ];
      bindsTo = [ "sway-session.target" ];
      enable = mkDefault sway.enable;
      wantedBy = [ "sway-session.target" ];
      serviceConfig = {
        ExecStart = "${pasystray}/bin/pasystray -N none";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };
    waybar.path = [
      bash
      curl
      gtklock.package
      power-menu
      theme-toggle
      waybar-yubikey
    ];
  };
}
