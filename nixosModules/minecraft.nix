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
    networking.firewall.allowedTCPPorts = [ 39059 ];
    thoughtfull.impermanence.user = {
      directories = [
        {
          directory = ".local/share/hmcl";
          mode = "0700";
        }
        ".minecraft"
      ];
      files = [
        {
          file = ".hmcl/hmcl.json";
          parentDirectory = {
            mode = "0700";
          };
        }
      ];
    };
  };
  options.thoughtfull.programs.minecraft.enable = mkEnableOption "minecraft";
}
