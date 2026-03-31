{ config, lib, pkgs, ... }:
let
  inherit (lib) mkDefault mkIf;
  inherit (pkgs) cups-brother-mfcl2750dw;
  cfg = config.services.printing;
in
{
  services.printing = {
    drivers = mkIf cfg.enable [ cups-brother-mfcl2750dw ];
    enable = mkDefault config.thoughtfull.graphical.enable;
  };
  thoughtfull.user.extraGroups = mkIf cfg.enable [ "lpadmin" ];
}
