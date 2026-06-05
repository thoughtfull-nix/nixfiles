{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault mkEnableOption mkIf;
  inherit (pkgs) gh;
  inherit (pkgs.thoughtfull) nixfiles pins uns;
in
{
  config = mkIf graphical.enable {
    environment.systemPackages = [
      gh
      nixfiles
      pins
      uns
    ];
    gtk.iconCache.enable = mkDefault true;
    hardware.bluetooth.enable = mkDefault true;
    networking = {
      domain = mkDefault "thoughtfull.systems";
      networkmanager.enable = mkDefault true;
    };
    programs = {
      firefox.enable = mkDefault true;
      sway.enable = mkDefault true;
      zsh.enable = mkDefault true;
    };
    services = {
      emacs.enable = mkDefault true;
      openssh.enable = mkDefault true;
      restic.thoughtfull.enable = mkDefault true;
      syncthing.enable = mkDefault true;
      xremap.enable = mkDefault true;
    };
    systemd.user.services.mako.enable = mkDefault true;
    thoughtfull = {
      backlight.enable = mkDefault true;
      impermanence = {
        disko.enable = mkDefault true;
        enable = mkDefault true;
        user.directories = [ ".config/dconf" ];
      };
      monitoring = {
        enable = mkDefault true;
        services = [
          "sshd"
          "syncthing"
          "restic-backups-default"
        ];
      };
      programs = {
        dictation.enable = mkDefault true;
        obsidian.enable = mkDefault true;
      };
      user.extraGroups = [ "wheel" ];
    };
  };
  options.thoughtfull.graphical.enable = mkEnableOption "graphical UI configuration";
}
