{ ... }:
{
  modules = [
    (
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.devenv ];
        imports = [
          ./hydor/hardware-configuration.nix
        ];
        networking = {
          domain = "thoughtfull.systems";
          hostName = "hydor";
          networkmanager.enable = true;
        };
        programs = {
          firefox.enable = true;
          git = {
            config.user = {
              email = "technosophist@thoughtfull.systems";
              signingkey = "DF2034C6";
            };
            enable = true;
          };
          sway.enable = true;
          zsh.enable = true;
        };
        services = {
          emacs.enable = true;
          openssh.enable = true;
          syncthing = {
            enable = true;
            settings.folders = {
              archive.enable = true;
              obsidian.enable = true;
              obsidian-work.enable = true;
              org.enable = true;
              org-work.enable = true;
            };
            thoughtfull.passwordFile = ./hydor/secrets/syncthing-passphrase.age;
          };
          xremap.enable = true;
        };
        system.stateVersion = "25.11";
        thoughtfull = {
          # Bootstrap images have no agenix-decrypted credentials, so the
          # binary cache substituter and daily pull timer must stay off
          # until the host is provisioned. The bootstrap flow evaluates
          # the flake locally.
          binaryCache.enable = false;
          systemPull.enable = false;
          graphical.enable = true;
          impermanence = {
            disko = {
              enable = true;
              encrypted.device = "/dev/nvme0n1";
            };
            enable = true;
          };
          user = {
            extraGroups = [ "wheel" ];
            hashedPasswordFile = ./hydor/secrets/hashed-user-passphrase.age;
          };
        };
      }
    )
  ];
  system = "x86_64-linux";
}
