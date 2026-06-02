{ ... }:
{
  modules = [
    (
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.devenv ];
        imports = [
          ./BOOTSTRAP/hardware-configuration.nix
        ];
        networking = {
          domain = "thoughtfull.systems";
          hostName = "BOOTSTRAP";
          networkmanager.enable = true;
        };
        programs = {
          firefox.enable = true;
          git.enable = true;
          sway.enable = true;
          zsh.enable = true;
        };
        services = {
          emacs.enable = true;
          openssh.enable = true;
          xremap.enable = true;
        };
        system.stateVersion = "25.11";
        thoughtfull = {
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
            hashedPasswordFile = ./BOOTSTRAP/secrets/hashed-user-passphrase.age;
            name = "technosophist";
          };
        };
      }
    )
  ];
  system = "x86_64-linux";
}
