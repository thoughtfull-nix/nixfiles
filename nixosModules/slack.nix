{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) graphical;
  inherit (config.thoughtfull.programs) slack;
  inherit (lib) mkEnableOption mkIf;
in
{
  config = {
    environment.systemPackages = mkIf slack.enable [ pkgs.slack ];
    thoughtfull.impermanence.user.directories = mkIf slack.enable [
      {
        directory = ".config/Slack";
        mode = "0700";
      }
    ];
  };
  options.thoughtfull.programs.slack.enable = mkEnableOption "slack" // {
    default = graphical.enable;
  };
}
