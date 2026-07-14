{ lib, pkgs, ... }:
let
  inherit (pkgs)
    bash
    kanshi
    procps
    symlinkJoin
    ;
  inherit (lib) writeFileScriptBin;
  waybar-displays = writeFileScriptBin {
    name = "waybar-displays";
    replacements = {
      bash = "${bash}/bin/bash";
    };
    src = ./waybar-displays/waybar-displays.bash;
  };
  kanshi-active = writeFileScriptBin {
    name = "kanshi-active";
    replacements = {
      bash = "${bash}/bin/bash";
      pkill = "${procps}/bin/pkill";
    };
    src = ./waybar-displays/kanshi-active.bash;
  };
  kanshi-toggle = writeFileScriptBin {
    name = "kanshi-toggle";
    replacements = {
      bash = "${bash}/bin/bash";
      kanshictl = "${kanshi}/bin/kanshictl";
    };
    src = ./waybar-displays/kanshi-toggle.bash;
  };
in
symlinkJoin {
  name = "waybar-displays";
  paths = [
    kanshi-active
    kanshi-toggle
    waybar-displays
  ];
}
