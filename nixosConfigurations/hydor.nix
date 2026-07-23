{ inputs, ... }:
{
  modules = [
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-6th-gen
    (
      { ... }:
      {
        boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
        imports = [
          ./hydor/hardware-configuration.nix
        ];
        networking.hostName = "hydor";
        services.syncthing = {
          settings.folders = {
            archive.enable = true;
            obsidian.enable = true;
            obsidian-work.enable = true;
            org.enable = true;
            org-work.enable = true;
          };
          thoughtfull.passwordFile = ./hydor/secrets/syncthing-passphrase.age;
        };
        system.stateVersion = "25.11";
        thoughtfull = {
          binaryCache.awsCredentialsFile = ./hydor/secrets/nix-cache-credentials.age;
          claudeDesktop.enable = true;
          dev.enable = true;
          githubToken.tokenFile = ./hydor/secrets/github-access-token.age;
          graphical.enable = true;
          impermanence.disko = {
            boot.size = "512M";
            encrypted.device = "/dev/nvme0n1";
            swap.size = "4G";
          };
          programs.minecraft.enable = true;
          user.hashedPasswordFile = ./hydor/secrets/hashed-user-passphrase.age;
          vpn.configFile = ./hydor/secrets/vpn-config.age;
        };
      }
    )
  ];
  system = "x86_64-linux";
}
