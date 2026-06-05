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
        system.stateVersion = "25.05";
        thoughtfull = {
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
