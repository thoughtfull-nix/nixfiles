{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) graphical;
  inherit (config.thoughtfull.programs) obsidian;
  inherit (lib) mkEnableOption mkIf;
in
{
  config = {
    environment.systemPackages = mkIf obsidian.enable [ pkgs.obsidian ];
    thoughtfull.impermanence.user.directories = [ ".config/obsidian" ];
  };
  options.thoughtfull.programs.obsidian.enable = mkEnableOption "obsidian" // {
    default = graphical.enable;
  };
}
