{ thoughtfull, ... }:
{
  boot.loader = {
    efi.canTouchEfiVariables = true;
    grub.enable = false;
    systemd-boot.enable = true;
  };
  environment.persistence."/persistent" = {
    enable = true;
    hideMounts = true;
    directories = [
      "/etc/NetworkManager/system-connections"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/log"
    ];
    files = [
      "/etc/machine-id"
    ];
  };
  fileSystems."/persistent".neededForBoot = true;
  imports = with thoughtfull.nixosModules; [
    ./disko.nix
    ./hardware-configuration.nix
    dvorak
    fonts
  ];
  networking = {
    domain = "thoughtfull.systems";
    hostName = "asaph";
    useDHCP = true;
    wireless = {
      enable = true;
      userControlled.enable = true;
    };
  };
  programs.zsh.enable = true;
  services.openssh.enable = true;
  system.stateVersion = "25.05";
  users.users.technosophist = {
    extraGroups = [ "wheel" ];
    password = "asaph";
  };
}
