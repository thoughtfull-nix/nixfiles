{ lib, pkgs, ... }:
let
  inherit (pkgs)
    bash
    brightnessctl
    coreutils
    libnotify
    pulseaudio
    replaceVars
    symlinkJoin
    ;
  inherit (lib) writeFileScriptBin;
  brightness-status = writeFileScriptBin (
    let
      color = "ffffff";
      size = 24;
      brightness-high-icon = replaceVars ./brightness/brightness-high.svg {
        inherit color size;
      };
      brightness-low-icon = replaceVars ./brightness/brightness-low.svg {
        inherit color size;
      };
      brightness-med-icon = replaceVars ./brightness/brightness-med.svg {
        inherit color size;
      };
    in
    {
      name = "brightness-status";
      replacements = {
        bash = "${bash}/bin/bash";
        brightnessctl = "${brightnessctl}/bin/brightnessctl";
        cut = "${coreutils}/bin/cut";
        inherit
          brightness-low-icon
          brightness-med-icon
          brightness-high-icon
          ;
        notify-send = "${libnotify}/bin/notify-send";
      };
      src = ./brightness/brightness-status.bash;
    }
  );
  brightness-decrease = writeFileScriptBin {
    name = "brightness-decrease";
    replacements = {
      bash = "${bash}/bin/bash";
      brightnessctl = "${brightnessctl}/bin/brightnessctl";
      paplay = "${pulseaudio}/bin/paplay";
      brightness-status = "${brightness-status}/bin/brightness-status";
      brightness-pop = "${./brightness/brightness-pop.ogg}";
    };
    src = ./brightness/brightness-decrease.bash;
  };
  brightness-increase = writeFileScriptBin {
    name = "brightness-increase";
    replacements = {
      bash = "${bash}/bin/bash";
      brightnessctl = "${brightnessctl}/bin/brightnessctl";
      paplay = "${pulseaudio}/bin/paplay";
      brightness-status = "${brightness-status}/bin/brightness-status";
      brightness-pop = "${./brightness/brightness-pop.ogg}";
    };
    src = ./brightness/brightness-increase.bash;
  };
in
symlinkJoin {
  name = "brightness";
  paths = [
    brightness-status
    brightness-decrease
    brightness-increase
  ];
}
