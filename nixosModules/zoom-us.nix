{
  config,
  lib,
  ...
}:
let
  inherit (config.programs) zoom-us;
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault mkIf;
in
{
  config = {
    programs.zoom-us.enable = mkDefault graphical.enable;
    security.rtkit.enable = mkDefault zoom-us.enable;
    thoughtfull.impermanence.user = mkIf zoom-us.enable {
      directories = [
        {
          directory = ".zoom";
          mode = "0700";
        }
      ];
      files = [
        ".config/zoom.conf"
        ".config/zoomus.conf"
      ];
    };
  };
}
