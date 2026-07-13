{ ... }:
{
  modules = [
    (
      { ... }:
      {
        imports = [
          ./sedna/hardware-configuration.nix
        ];
        networking.hostName = "sedna";
        services.syncthing.thoughtfull = {
          certFile = ./sedna/secrets/syncthing-cert.age;
          keyFile = ./sedna/secrets/syncthing-key.age;
          passwordFile = ./sedna/secrets/syncthing-passphrase.age;
        };
        system.stateVersion = "25.05";
        thoughtfull = {
          binaryCache.awsCredentialsFile = ./sedna/secrets/nix-cache-host-credentials.age;
          dev.enable = true;
          graphical.enable = true;
          impermanence.disko = {
            boot.size = "1G";
            encrypted.device = "/dev/nvme0n1";
            swap.size = "64G";
          };
          monitoring.services = [
            "mako"
            "test-failure"
          ];
          user.hashedPasswordFile = ./sedna/secrets/hashed-user-passphrase.age;
        };
      }
    )
  ];
  system = "x86_64-linux";
}
