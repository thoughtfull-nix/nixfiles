{ inputs, ... }:
{
  modules = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    (
      {
        lib,
        pkgs,
        ...
      }:
      {
        environment.systemPackages =
          with pkgs;
          with inputs.disko.packages.${pkgs.stdenv.hostPlatform.system};
          [
            disko
            jq
            tmux
            usbutils
          ];
        networking = {
          # set the hostname from dhcp (or default to "nixos")
          hostName = "";
        };
        programs = {
          git = {
            enable = true;
            config.user = {
              email = "technosophist@thoughtfull.systems";
              signingkey = "DF2034C6";
            };
          };
          zsh.enable = true;
        };
        security = {
          # among other things, this is necessary to set the hostname from dhcp
          polkit.enable = true;
          sudo.extraRules = [
            {
              commands = [
                {
                  command = "ALL";
                  options = [ "NOPASSWD" ];
                }
              ];
              groups = [ "wheel" ];
            }
          ];
        };
        services = {
          emacs.enable = true;
          openssh.enable = true;
          xremap.enable = true;
        };
        system.stateVersion = lib.trivial.release;
        systemd.services.sshd-keygen.enable = true;
        thoughtfull = {
          impermanence.enable = false;
          user = {
            extraGroups = [ "wheel" ];
            name = "technosophist";
            password = "nixos";
          };
        };
      }
    )
  ];
  system = "x86_64-linux";
}
