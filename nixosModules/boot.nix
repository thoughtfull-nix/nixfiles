{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkIf
    mkMerge
    mkOverride
    ;
  rpi4 = config.thoughtfull.rpi4.enable;
in
{
  config = mkMerge [
    { boot.initrd.systemd.enable = mkDefault true; }
    (mkIf (!rpi4) {
      boot = {
        initrd.luks.devices.encrypted.crypttabExtraOpts = [
          "fido2-device=auto"
          "token-timeout=5s"
        ];
        loader = {
          efi.canTouchEfiVariables = mkDefault true;
          grub.enable = mkDefault false;
          systemd-boot.enable = mkDefault true;
        };
      };
    })
    (mkIf rpi4 {
      boot.initrd = {
        network.ssh = {
          enable = mkDefault true;
          authorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
          port = mkDefault 222;
        };
        systemd = {
          network = {
            enable = mkOverride 900 true;
            networks."10-end0" = {
              matchConfig.Name = mkDefault "end0";
              networkConfig.DHCP = mkDefault "yes";
            };
          };
          users.root.shell = mkOverride 900 "/bin/systemd-tty-ask-password-agent";
        };
      };
    })
  ];
}
