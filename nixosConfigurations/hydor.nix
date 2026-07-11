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
          claudeDesktop.enable = true;
          dev.enable = true;
          githubToken.tokenFile = ./shared/secrets/github-access-token.age;
          graphical.enable = true;
          impermanence.disko = {
            boot.size = "512M";
            encrypted.device = "/dev/nvme0n1";
            swap.size = "4G";
          };
          user.hashedPasswordFile = ./hydor/secrets/hashed-user-passphrase.age;
        };
      }
    )
  ];
  system = "x86_64-linux";
}
