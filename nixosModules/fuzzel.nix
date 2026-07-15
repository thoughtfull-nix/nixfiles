{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkPackageOption
    ;
  cfg = config.thoughtfull.programs.fuzzel;
  wlr = config.xdg.portal.wlr;
in
{
  config = mkIf cfg.enable {
    environment = {
      etc."xdg/fuzzel/fuzzel.ini".source = ./fuzzel/fuzzel.ini;
      systemPackages = [ cfg.package ];
    };
    xdg.portal.wlr.settings.screencast = mkIf wlr.enable {
      chooser_type = mkDefault "dmenu";
      chooser_cmd = mkDefault "/run/current-system/sw/bin/fuzzel -d --width 80";
    };
  };
  options.thoughtfull.programs.fuzzel = {
    enable = mkEnableOption "fuzzel";
    package = mkPackageOption pkgs "fuzzel" {
      default = "fuzzel";
    };
  };
}
