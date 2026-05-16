{ inputs, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkDefault mkForce;
  cfgImpermanence = config.thoughtfull.impermanence;
  inherit (inputs)
    agenix
    disko
    impermanence
    kryptonix
    self
    ;
  system = config.nixpkgs.localSystem.system;
in
{
  boot.loader.timeout = mkForce 2;

  environment.systemPackages = [
    pkgs.thoughtfull.nixfiles
  ]
  ++ lib.optional cfgImpermanence.disko.enable disko.packages.${system}.disko;

  # Import all flake input modules
  imports = [
    agenix.nixosModules.default
    disko.nixosModules.default
    impermanence.nixosModules.default
    kryptonix.nixosModules.default

    # Load all modules in nixosModules. Each module is imported unconditionally and should use
    # options for conditional configuration. If a module needs auxiliary files, then it should
    # use a directory with the same name as the module (e.g. './foo.nix' should use files in
    # './foo/').
    ./agenix.nix
    ./avahi.nix
    ./backlight.nix
    ./bluetooth.nix
    ./boot.nix
    ./claude.nix
    ./clojure.nix
    ./dictation.nix
    ./discord.nix
    ./docker.nix
    ./dvorak.nix
    ./emacs.nix
    ./firefox.nix
    ./fonts.nix
    ./foot.nix
    ./fuzzel.nix
    ./git.nix
    ./gnupg.nix
    ./graphical.nix
    ./gtklock.nix
    ./impermanence.nix
    ./installer.nix
    ./java.nix
    ./javascript.nix
    ./less.nix
    ./mako.nix
    ./monitoring.nix
    ./obsidian.nix
    ./openssh.nix
    ./pipewire.nix
    ./printing.nix
    ./restic.nix
    ./rpi4.nix
    ./rust.nix
    ./screenshot.nix
    ./slack.nix
    ./sway.nix
    ./swayidle.nix
    ./syncthing.nix
    ./terminal.nix
    ./usb.nix
    ./user.nix
    ./vpn.nix
    ./weather.nix
    ./xremap.nix
    ./yubikey.nix
    ./zoom-us.nix
    ./zsh.nix
  ];

  nix = {
    settings.trusted-users = [ "@wheel" ];
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  nixpkgs = {
    config.allowUnfree = mkDefault true;
    overlays = [
      self.overlays.emacs
      self.overlays.thoughtfull
      self.overlays.unstable
    ];
  };
}
