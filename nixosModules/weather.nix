{
  config,
  lib,
  thoughtfull,
  ...
}:
let
  inherit (config.programs) waybar;
  inherit (config.thoughtfull) user weather;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  inherit (thoughtfull.pkgs) waybar-weather;
in
{
  config = mkIf weather.enable {
    age.secrets.openweathermap-api-key = {
      file = weather.apiKeyFile;
      owner = mkDefault user.name;
      group = mkDefault user.group;
    };
    environment.systemPackages = mkIf waybar.enable [ waybar-weather ];
    systemd.user.services.waybar.path = mkIf waybar.enable [ waybar-weather ];
    thoughtfull.impermanence.user = {
      directories = [
        ".cache/waybar-weather"
        ".config/waybar-weather"
      ];
    };
  };
  options.thoughtfull.weather = {
    apiKeyFile = mkOption {
      default = null;
      description = "Path to the .age file containing the OpenWeatherMap API key";
      type = types.nullOr types.path;
    };
    enable = mkEnableOption "weather widget" // {
      default = weather.apiKeyFile != null;
    };
  };
}
