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
  # EC2 instances boot from the amazon-image profile's own GRUB and have no
  # LUKS device, so the systemd-boot + FIDO2-LUKS unlock block below must not
  # apply (it would fight that bootloader and declare a phantom 'encrypted'
  # LUKS device).
  ec2 = config.thoughtfull.ec2.enable;
in
{
  config = mkMerge [
    { boot.initrd.systemd.enable = mkDefault true; }
    (mkIf (!rpi4 && !ec2) {
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
          authorizedKeyFiles = config.users.users.root.openssh.authorizedKeys.keyFiles;
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
