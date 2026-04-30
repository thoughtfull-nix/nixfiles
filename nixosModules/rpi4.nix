{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOverride
    ;
  cfg = config.thoughtfull.rpi4;
in
{
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !config.boot.initrd.network.ssh.enable
          || config.users.users.root.openssh.authorizedKeys.keys != [ ];
        message = "thoughtfull.rpi4.enable requires at least one root SSH authorized key for initrd remote unlock";
      }
    ];
    hardware.enableRedistributableFirmware = mkDefault true;
    networking = {
      networkmanager.enable = mkOverride 900 false;
      useNetworkd = mkDefault true;
    };
  };
  options.thoughtfull.rpi4.enable = mkEnableOption "Raspberry Pi 4 configuration";
}
