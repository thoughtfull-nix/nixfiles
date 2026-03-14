self: {
  default =
    {
      lib,
      ...
    }:
    let
      inherit (lib) mkDefault;
    in
    {
      boot.loader.timeout = lib.mkForce 2;
      # Load all modules in nixosModules.  Each module is imported unconditionally and should use
      # options for conditional configuration.  If a module needs auxiliary files, then it should
      # use a directory with the same name as the module (e.g. './foo.nix' should use files in
      # './foo/').
      imports = [
        ./nixosModules/agenix.nix
        ./nixosModules/avahi.nix
        ./nixosModules/backlight.nix
        ./nixosModules/bluetooth.nix
        ./nixosModules/claude.nix
        ./nixosModules/clojure.nix
        ./nixosModules/discord.nix
        ./nixosModules/docker.nix
        ./nixosModules/dvorak.nix
        ./nixosModules/emacs.nix
        ./nixosModules/firefox.nix
        ./nixosModules/fonts.nix
        ./nixosModules/foot.nix
        ./nixosModules/fuzzel.nix
        ./nixosModules/git.nix
        ./nixosModules/gnupg.nix
        ./nixosModules/graphical.nix
        ./nixosModules/gtklock.nix
        ./nixosModules/impermanence.nix
        ./nixosModules/java.nix
        ./nixosModules/javascript.nix
        ./nixosModules/less.nix
        ./nixosModules/mako.nix
        ./nixosModules/monitoring.nix
        ./nixosModules/obsidian.nix
        ./nixosModules/openssh.nix
        ./nixosModules/pipewire.nix
        ./nixosModules/printing.nix
        ./nixosModules/restic.nix
        ./nixosModules/rust.nix
        ./nixosModules/slack.nix
        ./nixosModules/sway.nix
        ./nixosModules/swayidle.nix
        ./nixosModules/syncthing.nix
        ./nixosModules/terminal.nix
        ./nixosModules/user.nix
        ./nixosModules/vpn.nix
        ./nixosModules/weather.nix
        ./nixosModules/xremap.nix
        ./nixosModules/yubikey.nix
        ./nixosModules/zoom-us.nix
        ./nixosModules/zsh.nix
      ];
      nix = {
        settings.trusted-users = [ "@wheel" ];
        extraOptions = ''
          experimental-features = nix-command flakes
        '';
      };
      nixpkgs = {
        config.allowUnfree = mkDefault true;
        overlays = [ self.overlays.emacs ];
      };
    };
}
