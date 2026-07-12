{ ... }:
{
  modules = [
    (
      { ... }:
      {
        imports = [
          ./aegle/hardware-configuration.nix
        ];
        networking.hostName = "aegle";
        services.syncthing.thoughtfull.passwordFile = ./aegle/secrets/syncthing-passphrase.age;
        system.stateVersion = "25.11";
        thoughtfull = {
          dev.enable = true;
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
