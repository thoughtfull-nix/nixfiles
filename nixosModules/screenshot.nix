{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkIf;
  inherit (pkgs) flameshot grim;
in
{
  config = mkIf graphical.enable {
    environment = {
      etc = mkIf sway.enable {
        "sway/config.d/screenshot.conf".text = ''
          bindsym --no-repeat Print exec flameshot gui -c
        '';
      };
      systemPackages = [
        flameshot
        grim
      ];
    };
    thoughtfull.impermanence.user.directories = [
      {
        directory = ".config/flameshot";
        mode = "0755";
      }
    ];
  };
}
