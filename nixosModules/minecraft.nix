{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull.programs) minecraft;
  inherit (lib) mkEnableOption mkIf;
in
{
  config = mkIf minecraft.enable {
    environment.systemPackages = [ pkgs.hmcl ];
    thoughtfull.impermanence.user = {
      directories = [
        ".local/share/hmcl"
        ".minecraft"
      ];
      files = [
        ".hmcl/hmcl.json"
      ];
    };
  };
  options.thoughtfull.programs.minecraft.enable = mkEnableOption "minecraft";
}
