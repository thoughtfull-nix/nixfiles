{
  lib,
  nixpkgs,
  pkgs,
  thoughtfull,
  ...
}:
{
  environment = {
    systemPackages = with pkgs; [
      emacs-nox
      git
      jq
      tmux
      usbutils
    ];
  };
  imports = with thoughtfull.nixosModules; [
    "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
    "${nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
    "${nixpkgs}/nixos/modules/profiles/all-hardware.nix"
    "${nixpkgs}/nixos/modules/profiles/base.nix"
    dvorak
    fonts
  ];
  isoImage = {
    compressImage = false;
    makeEfiBootable = true;
    makeUsbBootable = true;
  };
  networking = {
    domain = "thoughtfull.systems";
    hostName = "mehida";
    useDHCP = true;
    wireless = {
      enable = true;
      userControlled.enable = true;
    };
  };
  programs.zsh.enable = true;
  security.sudo.extraRules = [
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
  services.openssh.enable = true;
  system.stateVersion = lib.trivial.release;
  users.users.technosophist = {
    extraGroups = [ "wheel" ];
    password = "mehida";
  };
}
