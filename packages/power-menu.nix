{ lib, pkgs, ... }:
let
  inherit (pkgs.lib) makeOverridable;
  inherit (lib) writeFileScriptBin;
in
makeOverridable
  (
    {
      bash,
      fuzzel,
      sway,
      systemd,
    }:
    writeFileScriptBin {
      name = "power-menu";
      replacements = {
        bash = "${bash}/bin/bash";
        fuzzel = "${fuzzel}/bin/fuzzel";
        loginctl = "${systemd}/bin/loginctl";
        swaymsg = "${sway}/bin/swaymsg";
        systemctl = "${systemd}/bin/systemctl";
      };
      src = ./power-menu.bash;
    }
  )
  {
    inherit (pkgs)
      bash
      fuzzel
      sway
      systemd
      ;
  }
