{ ... }:
{
  modules = [
    (
      { ... }:
      {
        boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
        imports = [
          ./hydor/hardware-configuration.nix
        ];
        networking.hostName = "hydor";
        services = {
          syncthing = {
            settings.folders = {
              archive.enable = true;
              obsidian.enable = true;
              obsidian-work.enable = true;
              org.enable = true;
              org-work.enable = true;
            };
            thoughtfull.passwordFile = ./hydor/secrets/syncthing-passphrase.age;
          };
        };
        system.stateVersion = "25.11";
        thoughtfull = {
          dev.enable = true;
          graphical.enable = true;
          impermanence.disko = {
            # boot.size = "1G";
            encrypted.device = "/dev/nvme0n1";
            # swap.size = "64G";
          };
          user.hashedPasswordFile = ./hydor/secrets/hashed-user-passphrase.age;
        };
      }
    )
  ];
  system = "x86_64-linux";
}
