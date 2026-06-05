{ ... }:
{
  modules = [
    (
      { ... }:
      {
        imports = [
          ./BOOTSTRAP/hardware-configuration.nix
        ];
        networking.hostName = "BOOTSTRAP";
        system.stateVersion = "25.11";
        thoughtfull = {
          dev.enable = true;
          graphical.enable = true;
          impermanence.disko = {
            # boot.size = "512M";
            # encrypted.device = "/dev/nvme0n1";
            # swap.size = "4G";
          };
          user.hashedPasswordFile = ./BOOTSTRAP/secrets/hashed-user-passphrase.age;
        };
      }
    )
  ];
  system = "x86_64-linux";
}
