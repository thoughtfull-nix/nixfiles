{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf mkPackageOption;
  cfg = config.thoughtfull.programs.fuzzel;
in
{
  config.environment = mkIf cfg.enable {
    etc."xdg/fuzzel/fuzzel.ini".source = ./fuzzel/fuzzel.ini;
    systemPackages = [ cfg.package ];
  };
  options.thoughtfull.programs.fuzzel = {
    enable = mkEnableOption "fuzzel";
    package = mkPackageOption pkgs "fuzzel" {
      default = "fuzzel";
    };
  };
}
