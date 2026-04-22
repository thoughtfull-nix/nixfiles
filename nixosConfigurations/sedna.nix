{ ... }:
{
  modules = [
    (
      { pkgs, ... }:
      {
        boot = {
          binfmt.emulatedSystems = [ "aarch64-linux" ];
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
        environment.systemPackages = [
          pkgs.devenv
        ]
        ++ (with pkgs.thoughtfull; [
          nixfiles
          pins
          uns
        ]);
        hardware.bluetooth.enable = true;
        imports = [
          ./sedna/hardware-configuration.nix
        ];
        networking = {
          domain = "thoughtfull.systems";
          hostName = "sedna";
          # useDHCP = true;
          # wireless = {
          #   enable = true;
          #   userControlled.enable = true;
          # };
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
          java.package = pkgs.javaPackages.compiler.temurin-bin.jdk-25;
          sway.enable = true;
          zsh.enable = true;
        };
        services = {
          emacs.enable = true;
          openssh.enable = true;
          restic.thoughtfull.enable = true;
          syncthing = {
            enable = true;
            thoughtfull.passwordFile = ./sedna/secrets/syncthing-password.age;
          };
          xremap.enable = true;
        };
        system.stateVersion = "25.05";
        systemd.user.services.mako.enable = true;
        thoughtfull = {
          backlight.enable = true;
          claude.enable = true;
          clojure = {
            enable = true;
            # jdk.package = pkgs.javaPackages.compiler.temurin-bin.jdk-17;
          };
          graphical.enable = true;
          impermanence = {
            disko = {
              boot.size = "1G";
              enable = true;
              encrypted.device = "/dev/nvme0n1";
              swap.size = "64G";
            };
            enable = true;
            user.directories = [ "src" ];
          };
          monitoring = {
            enable = true;
            services = [
              "sshd"
              "syncthing"
              "restic-backups-default"
              "mako"
              "test-failure"
            ];
          };
          programs = {
            dictation.enable = true;
            obsidian.enable = true;
          };
          rust.enable = true;
          user = {
            extraGroups = [ "wheel" ];
            hashedPasswordFile = ./sedna/secrets/hashed-user-passphrase.age;
          };
        };
        time.timeZone = "America/New_York";
      }
    )
  ];
  system = "x86_64-linux";
}
