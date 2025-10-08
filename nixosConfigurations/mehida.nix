{
  lib,
  modulesPath,
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
    "${modulesPath}/installer/cd-dvd/channel.nix"
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
    "${modulesPath}/profiles/all-hardware.nix"
    "${modulesPath}/profiles/base.nix"
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
