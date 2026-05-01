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
        networking = {
          domain = "thoughtfull.systems";
          hostName = "tislit";
        };
        programs = {
          git = {
            config.user = {
              email = "technosophist@thoughtfull.systems";
              signingkey = "DF2034C6";
            };
            enable = true;
          };
          zsh.enable = true;
        };
        services = {
          emacs.enable = true;
          openssh.enable = true;
        };
        system.stateVersion = "25.11";
        thoughtfull = {
          impermanence = {
            disko = {
              boot.size = "1G";
              enable = true;
              encrypted.device = "/dev/sda";
              swap.size = "16G";
            };
            enable = true;
          };
          rpi4.enable = true;
          user = {
            extraGroups = [ "wheel" ];
            hashedPasswordFile = ./tislit/secrets/hashed-user-passphrase.age;
            name = "technosophist";
          };
        };
        time.timeZone = "America/New_York";
      }
    )
  ];
  system = "aarch64-linux";
}
