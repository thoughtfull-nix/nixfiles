{
  inputs,
  lib,
  modulesPath,
  pkgs,
  thoughtfull,
  ...
}:
{
  environment = {
    systemPackages =
      with pkgs;
      with inputs.disko.packages;
      [
        disko
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
    # set the hostname from dhcp (or default to "nixos")
    hostName = "";
    useDHCP = true;
    wireless = {
      enable = true;
      userControlled.enable = true;
    };
  };
  programs.zsh.enable = true;
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
  services.openssh.enable = true;
  system.stateVersion = lib.trivial.release;
  systemd.services.sshd-keygen.enable = true;
  thoughtfull.impermanence.enable = false;
  users.users.technosophist = {
    extraGroups = [ "wheel" ];
    password = "nixos";
  };
}
