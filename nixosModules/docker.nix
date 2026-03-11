{ config, lib, ... }:
let
  inherit (config.virtualisation) docker;
  inherit (lib) mkDefault mkIf;
in
{
  thoughtfull = {
    impermanence.directories = mkIf docker.enable [
      {
        directory = "/var/lib/docker";
        mode = "0750";
      }
    ];
    user.extraGroups = mkIf docker.enable [ "docker" ];
  };
  virtualisation.docker = {
    autoPrune = {
      enable = mkDefault true;
      flags = [ "--all" ];
      persistent = mkDefault true;
    };
    daemon.settings.live-restore = mkDefault true;
    storageDriver = mkDefault "overlay2";
  };
}
