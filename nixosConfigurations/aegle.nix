{ ... }:
{
  modules = [
    (
      { ... }:
      {
        imports = [
          ./aegle/hardware-configuration.nix
        ];
        # The external "USB 2.0 Camera" (Sonix, USB ID 1410:1410) reuses Novatel
        # Wireless's vendor ID, so the `option` USB-modem driver hijacks its
        # video/audio interfaces before uvcvideo/snd-usb-audio can bind, leaving
        # no /dev/video node. This machine uses no USB cellular modem, so
        # blacklisting `option` lets the camera bind correctly.
        boot.blacklistedKernelModules = [ "option" ];
        networking.hostName = "aegle";
        services.syncthing = {
          settings.folders = {
            obsidian-work.enable = true;
            org-work.enable = true;
          };
          thoughtfull.passwordFile = ./aegle/secrets/syncthing-passphrase.age;
        };
        system.stateVersion = "25.11";
        thoughtfull = {
          binaryCache.awsCredentialsFile = ./aegle/secrets/nix-cache-credentials.age;
          dev.enable = true;
          githubToken.tokenFile = ./aegle/secrets/github-access-token.age;
          graphical.enable = true;
          impermanence.disko = {
            boot.size = "1G";
            encrypted.device = "/dev/nvme0n1";
            swap.size = "64G";
          };
          user.hashedPasswordFile = ./aegle/secrets/hashed-user-passphrase.age;
        };
      }
    )
  ];
  system = "x86_64-linux";
}
