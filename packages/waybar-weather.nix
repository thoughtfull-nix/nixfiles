{ lib, pkgs, ... }:
let
  inherit (pkgs)
    bash
    curl
    emacs
    gnused
    jq
    symlinkJoin
    ;
  inherit (lib) writeFileScriptBin;
  waybar-weather = writeFileScriptBin {
    name = "waybar-weather";
    replacements = {
      bash = "${bash}/bin/bash";
      curl = "${curl}/bin/curl";
      jq = "${jq}/bin/jq";
      sed = "${gnused}/bin/sed";
    };
    src = ./waybar-weather/waybar-weather.bash;
  };
  waybar-weather-edit = writeFileScriptBin {
    name = "waybar-weather-edit";
    replacements = {
      bash = "${bash}/bin/bash";
      emacsclient = "${emacs}/bin/emacsclient";
    };
    src = ./waybar-weather/waybar-weather-edit.bash;
  };
in
symlinkJoin {
  name = "waybar-weather";
  paths = [
    waybar-weather
    waybar-weather-edit
  ];
}
