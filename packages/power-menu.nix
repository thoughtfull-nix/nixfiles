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
      gtklock,
      sway,
      systemd,
    }:
    writeFileScriptBin {
      name = "power-menu";
      replacements = {
        bash = "${bash}/bin/bash";
        fuzzel = "${fuzzel}/bin/fuzzel";
        gtklock = "${gtklock}/bin/gtklock";
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
      gtklock
      sway
      systemd
      ;
  }
