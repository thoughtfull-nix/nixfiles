{ inputs, ... }:
{
  modules = [
    "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (
      {
        lib,
        pkgs,
        ...
      }:
      {
        hardware.raspberry-pi."4".poe-hat.enable = true;
        # Fix: allow missing modules for other ARM platforms (Rockchip, Allwinner) that don't exist
        # on RPi4 See:
        # https://discourse.nixos.org/t/cannot-build-raspberry-pi-sdimage-module-dw-hdmi-not-found/71804
        boot.initrd.allowMissingModules = true;
        environment.systemPackages =
          with pkgs;
          with pkgs.thoughtfull;
          with inputs.disko.packages.aarch64-linux;
          [
            curl
            disko
            jq
            nixfiles
            pins
            tmux
            uns
            unzip
            usbutils
          ];
        hardware.enableRedistributableFirmware = true;
        # set the hostname from dhcp (or default to "nixos")
        networking.hostName = "";
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
          pcscd.enable = true;
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
  system = "aarch64-linux";
}
