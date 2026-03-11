{ config, lib, ... }:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault mkEnableOption mkIf;
in
{
  config = {
    gtk.iconCache.enable = mkDefault graphical.enable;
    thoughtfull.impermanence.user.directories = mkIf graphical.enable [ ".config/dconf" ];
  };
  options.thoughtfull.graphical.enable = mkEnableOption "graphical UI configuration";
}
