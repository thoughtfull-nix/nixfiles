{ inputs, ... }:
{
  modules = [
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x13-intel
    (
      { pkgs, ... }:
      {
        imports = [
          ./aegle/hardware-configuration.nix
        ];
        # The external "USB 2.0 Camera" (Sonix, USB ID 1410:1410) reuses Novatel
        # Wireless's vendor ID, so the `option` USB-modem driver hijacks its
        # video/audio interfaces before uvcvideo/snd-usb-audio can bind, leaving
        # no /dev/video node. This machine uses no USB cellular modem, so
        # blacklisting `option` lets the camera bind correctly.
        boot.blacklistedKernelModules = [ "option" ];
        environment = {
          etc."sway/config.d/workspaces.conf".source = ./aegle/sway/workspaces.conf;
          systemPackages = with pkgs; [
            libreoffice
            maven
            ngrok
            texlive.combined.scheme-full
            # file watcher: reflex make OR reflex -r '\.c$' make OR reflex -g '*c' make
            reflex
          ];
          variables.PSQL_PAGER = "${pkgs.less}/bin/less -S --header 2";
        };
        networking.hostName = "aegle";
        programs.git = {
          # Let git-lfs defer SSH connection multiplexing to ssh_config instead
          # of opening its own private control socket. Combined with the
          # ControlMaster config for github.com (see git.nix), this lets
          # git-lfs-transfer reuse the master connection git already opened for
          # the push, so an LFS-backed push needs a single YubiKey touch.
          config.lfs.ssh.automultiplex = false;
          lfs.enable = true;
        };
        services = {
          clamav = {
            daemon.enable = true;
            fangfrisch.enable = true;
            scanner.enable = true;
            updater.enable = true;
          };
          syncthing = {
            settings.folders = {
              obsidian-work.enable = true;
              org-work.enable = true;
            };
            thoughtfull.passwordFile = ./aegle/secrets/syncthing-passphrase.age;
          };
        };
        system.stateVersion = "25.11";
        thoughtfull = {
          binaryCache.awsCredentialsFile = ./aegle/secrets/nix-cache-credentials.age;
          dev.enable = true;
          githubToken.tokenFile = ./aegle/secrets/github-access-token.age;
          graphical.enable = true;
          impermanence = {
            disko = {
              boot.size = "1G";
              encrypted.device = "/dev/nvme0n1";
              swap.size = "64G";
            };
            user.directories = [ ".aws" ];
          };
          programs.sway.kanshi.configFile = ./aegle/kanshi/config;
          user = {
            hashedPasswordFile = ./aegle/secrets/hashed-user-passphrase.age;
            u2fKeyFiles = [
              ./aegle/secrets/u2f-primary-ywa258.age
              ./aegle/secrets/u2f-backup-ywc962.age
            ];
          };
        };
        virtualisation.docker.enable = true;
      }
    )
  ];
  system = "x86_64-linux";
}
