{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkDefault mkEnableOption mkIf;
in
{
  config = mkIf config.thoughtfull.fonts.enable {
    console = {
      earlySetup = mkDefault true;
      font = mkDefault "ter-116n";
      packages = [ pkgs.terminus_font ];
    };
  };
  options.thoughtfull.fonts.enable = mkEnableOption "fonts" // {
    default = true;
  };
}
