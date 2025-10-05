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
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/log"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
  fileSystems."/persistent".neededForBoot = true;
  imports = with thoughtfull.nixosModules; [
    ./disko.nix
    ./hardware-configuration.nix
    dvorak
    fonts
    # thoughtfull.diskoConfigurations.gemariah
  ];
  networking = {
    domain = "thoughtfull.systems";
    hostName = "gemariah";
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
    password = "mehida";
  };
}
