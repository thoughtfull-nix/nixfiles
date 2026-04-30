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
    assertions = [
      {
        assertion = config.users.users.root.openssh.authorizedKeys.keys != [ ];
        message = "thoughtfull.rpi4.enable requires at least one root SSH authorized key for initrd remote unlock";
      }
    ];
    hardware.enableRedistributableFirmware = mkDefault true;
    networking = {
      networkmanager.enable = mkDefault false;
      useNetworkd = mkDefault true;
    };
  };
  options.thoughtfull.rpi4.enable = mkEnableOption "Raspberry Pi 4 configuration";
}
