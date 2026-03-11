{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (lib) mkDefault;
in
{
  fonts.packages = [ pkgs.nerd-fonts.fira-code ];
  programs = {
    foot.enable = mkDefault sway.enable;
    starship = {
      enable = mkDefault true;
      presets = [ "nerd-font-symbols" ];
    };
  };
}
