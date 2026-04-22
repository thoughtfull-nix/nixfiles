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
    # Fix: allow missing modules for other ARM platforms (Rockchip, Allwinner) that don't exist
    # on RPi4. See:
    # https://discourse.nixos.org/t/cannot-build-raspberry-pi-sdimage-module-dw-hdmi-not-found/71804
    # Some modules (like aes_generic) are built-in on ARM, not loadable
    boot.initrd.allowMissingModules = mkDefault true;
    hardware.enableRedistributableFirmware = mkDefault true;
  };
  options.thoughtfull.rpi4.enable = mkEnableOption "Raspberry Pi 4 configuration";
}
