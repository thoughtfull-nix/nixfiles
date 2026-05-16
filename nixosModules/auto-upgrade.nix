{ config, lib, ... }:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault;
in
{
  system.autoUpgrade = {
    enable = mkDefault true;
    flake = mkDefault "github:thoughtfull-nix/nixfiles";
    dates = mkDefault (if graphical.enable then "*-*-* 12:00:00" else "*-*-* 03:00:00");
    randomizedDelaySec = mkDefault "15min";
    # Headless hosts may reboot for kernel updates; graphical hosts stage the
    # new kernel and apply it on the user's next manual reboot.
    allowReboot = mkDefault (!graphical.enable);
  };
}
