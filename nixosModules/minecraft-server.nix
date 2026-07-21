{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull.services) minecraft-server;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    ;
in
{
  config = mkIf minecraft-server.enable {
    services.minecraft-server = {
      declarative = mkDefault true;
      enable = mkDefault true;
      eula = mkDefault true;
      jvmOpts = "-Xmx3072M -Xms3072M";
      openFirewall = mkDefault true;
      package = mkDefault pkgs.papermc;
      serverProperties = {
        difficulty = mkDefault 2;
        gamemode = mkDefault 0;
        max-players = mkDefault 5;
        motd = mkDefault "Survive and thrive!";
        server-port = mkDefault 25565;
        simulation-distance = mkDefault 4;
        view-distance = mkDefault 6;
      };
    };
    thoughtfull.impermanence.directories = [
      {
        directory = config.services.minecraft-server.dataDir;
        mode = "0750";
        group = "minecraft";
        user = "minecraft";
      }
    ];
  };
  options.thoughtfull.services.minecraft-server.enable = mkEnableOption "minecraft-server";
}
