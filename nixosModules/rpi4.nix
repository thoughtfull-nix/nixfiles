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
    # Fix: allow missing modules for ARM platforms
    # Some modules (like aes_generic) are built-in on ARM, not loadable
    boot.initrd.allowMissingModules = mkDefault true;
    hardware.enableRedistributableFirmware = mkDefault true;
  };
  options.thoughtfull.rpi4.enable = mkEnableOption "Raspberry Pi 4 configuration";
}
