{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (lib) mkDefault mkEnableOption mkIf;
  cfg = config.thoughtfull.programs.commonplace;
in
{
  config = mkIf cfg.enable {
    environment = {
      etc."sway/config.d/commonplace.conf" = mkIf sway.enable { source = ./commonplace/sway.conf; };
      systemPackages = [ pkgs.commonplace ];
    };
    thoughtfull.impermanence.user.directories = [ ".local/share/commonplace" ];
    xdg.mime.defaultApplications."x-scheme-handler/commonplace" =
      mkDefault "systems.thoughtfull.Commonplace.desktop";
  };
  options.thoughtfull.programs.commonplace.enable = mkEnableOption "commonplace";
}
