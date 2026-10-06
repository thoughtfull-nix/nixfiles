{
  config,
  lib,
  options,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOverride
    optionalAttrs
    ;
  cfg = config.thoughtfull.rpi4;
  hasNixosHardware = options.hardware ? raspberry-pi && options.hardware.raspberry-pi ? "4";
in
{
  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion =
            !config.boot.initrd.network.ssh.enable
            || config.users.users.root.openssh.authorizedKeys.keyFiles != [ ];
          message = "thoughtfull.rpi4.enable requires at least one root SSH authorized key for initrd remote unlock";
        }
      ];
      hardware.enableRedistributableFirmware = mkDefault true;
      networking = {
        networkmanager.enable = mkOverride 900 false;
        useNetworkd = mkOverride 900 true;
      };
    }
    (mkIf cfg.poeHat.enable (
      {
        assertions = [
          {
            assertion = hasNixosHardware;
            message = "thoughtfull.rpi4.poeHat.enable requires nixos-hardware's raspberry-pi-4 module";
          }
        ];
      }
      # The stock overlay declares brcm,bcm2835, so it needs dtmerge, which skips
      # the compatible check that would otherwise drop it from bcm2711 DTBs.
      // optionalAttrs hasNixosHardware {
        hardware = {
          deviceTree.overlays = [
            {
              name = "rpi-poe";
              dtboFile = "${config.boot.kernelPackages.kernel}/dtbs/overlays/rpi-poe.dtbo";
              filter = "bcm2711-rpi-4-b.dtb";
            }
          ];
          raspberry-pi."4".apply-overlays-dtmerge.enable = mkDefault true;
        };
      }
    ))
  ]);
  options.thoughtfull.rpi4 = {
    enable = mkEnableOption "Raspberry Pi 4 configuration";
    poeHat.enable = mkEnableOption "the Raspberry Pi PoE HAT fan";
  };
}
