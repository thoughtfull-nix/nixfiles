{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkDefault mkIf mkMerge;
  cfg = config.thoughtfull.graphical;
  sway = config.programs.sway;
in
{
  config = mkMerge [
    (mkIf cfg.enable {
      services.udisks2.enable = mkDefault true;
    })
    (mkIf sway.enable {
      environment.systemPackages = [ pkgs.thoughtfull.usb-menu ];
    })
  ];
}
