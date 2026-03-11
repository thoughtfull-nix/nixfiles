{
  modules = [
    (
      { pkgs, thoughtfull, ... }:
      {
        boot = {
          initrd = {
            luks.devices.encrypted.crypttabExtraOpts = [
              "fido2-device=auto"
              "token-timeout=5s"
            ];
            systemd.enable = true;
          };
          loader = {
            efi.canTouchEfiVariables = true;
            grub.enable = false;
            systemd-boot.enable = true;
          };
        };
        environment.systemPackages = [ pkgs.devenv ];
        imports = with thoughtfull.nixosModules; [
          ./BOOTSTRAP/hardware-configuration.nix
        ];
        networking = {
          domain = "thoughtfull.systems";
          hostName = "BOOTSTRAP";
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
          xremap.enable = true;
        };
        system.stateVersion = "25.05";
        thoughtfull = {
          graphical.enable = true;
          impermanence = {
            disko = {
              enable = true;
              encrypted.device = "/dev/sda";
            };
            enable = true;
          };
          user = {
            extraGroups = [ "wheel" ];
            hashedPasswordFile = ./BOOTSTRAP/secrets/hashed-user-passphrase.age;
            name = "technosophist";
          };
        };
      }
    )
  ];
  system = "x86_64-linux";
}
