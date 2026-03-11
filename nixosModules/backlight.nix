{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs) bash brightnessctl writeScript;
  inherit (lib) mkEnableOption mkIf;
  cfg = config.thoughtfull.backlight;
  dim-screen = writeScript "dim-screen" ''
    #!${bash}/bin/bash

    case ''${1} in
      ac)
        ${brightnessctl}/bin/brightnessctl s 100%
        ;;
      bat)
        ${brightnessctl}/bin/brightnessctl s 50%
        ;;
    esac
  '';
in
{
  config.services.udev = mkIf cfg.enable {
    extraRules = ''
      SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="${dim-screen} bat"
      SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="${dim-screen} ac"
    '';
  };
  options.thoughtfull.backlight.enable = mkEnableOption "backlight management";
}
