{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services) minecraft-server;
  inherit (lib)
    mkDefault
    mkIf
    ;
in
{
  config = mkIf minecraft-server.enable {
    services.minecraft-server = {
      declarative = mkDefault true;
      eula = mkDefault true;
      openFirewall = mkDefault true;
      package = mkDefault pkgs.thoughtfull.papermc-26-2;
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
}
