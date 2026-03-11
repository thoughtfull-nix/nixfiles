{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull.programs) discord;
  inherit (lib) mkEnableOption mkIf;
in
{
  config = {
    environment.systemPackages = mkIf discord.enable [
      (pkgs.discord.override { withTTS = true; })
    ];
    thoughtfull.impermanence.user.directories = mkIf discord.enable [
      {
        directory = ".config/discord";
        mode = "0755";
      }
    ];
  };
  options.thoughtfull.programs.discord.enable = mkEnableOption "discord";
}
