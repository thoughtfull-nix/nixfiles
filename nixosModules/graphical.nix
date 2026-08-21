{
  config,
  lib,
  ...
}:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    ;
in
{
  config = mkIf graphical.enable {
    gtk.iconCache.enable = mkDefault true;
    hardware.bluetooth.enable = mkDefault true;
    networking.networkmanager.enable = mkDefault true;
    programs = {
      evince.enable = mkDefault true;
      firefox.enable = mkDefault true;
      sway.enable = mkDefault true;
    };
    services = {
      emacs.enable = mkDefault true;
      xremap.enable = mkDefault true;
    };
    systemd.user.services.mako.enable = mkDefault true;
    thoughtfull = {
      impermanence.user.directories = [ ".config/dconf" ];
      user.extraGroups = [ "networkmanager" ];
      programs = {
        dictation.enable = mkDefault true;
        obsidian.enable = mkDefault true;
      };
    };
  };
  options.thoughtfull.graphical.enable = mkEnableOption "graphical UI configuration";
}
