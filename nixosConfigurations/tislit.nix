{ inputs, ... }:
{
  modules = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.devenv ];
        hardware.raspberry-pi."4".poe-hat.enable = true;
        imports = [
          ./tislit/hardware-configuration.nix
        ];
        networking.hostName = "tislit";
        services = {
          emacs.enable = true;
          minecraft-server = {
            enable = true;
            jvmOpts = "-Xmx3072M -Xms3072M";
          };
          openssh.enable = true;
          restic.thoughtfull = {
            enable = true;
            # tislit is the always-on host, so it owns the daily repository-wide
            # prune; every other host only backs up hourly.
            prune.enable = true;
          };
          syncthing = {
            enable = true;
            settings.folders = {
              archive.enable = true;
              obsidian.enable = true;
              org.enable = true;
            };
            thoughtfull.passwordFile = ./tislit/secrets/syncthing-passphrase.age;
          };
        };
        system.stateVersion = "25.11";
        thoughtfull = {
          binaryCache.awsCredentialsFile = ./tislit/secrets/nix-cache-credentials.age;
          impermanence = {
            disko = {
              boot.size = "1G";
              encrypted.device = "/dev/sda";
              swap.size = "16G";
            };
          };
          rpi4.enable = true;
          user = {
            extraGroups = [ "wheel" ];
            hashedPasswordFile = ./tislit/secrets/hashed-user-passphrase.age;
            name = "technosophist";
          };
        };
      }
    )
  ];
  system = "aarch64-linux";
}
