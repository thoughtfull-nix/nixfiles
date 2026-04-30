{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkDefault mkEnableOption mkIf;
  cfg = config.thoughtfull.rpi4;
in
{
  config = mkIf cfg.enable {
    hardware.enableRedistributableFirmware = mkDefault true;
  };
  options.thoughtfull.rpi4.enable = mkEnableOption "Raspberry Pi 4 configuration";
}
