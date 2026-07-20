{ lib, pkgs, ... }:
let
  inherit (pkgs)
    bash
    libcanberra-gtk3
    libnotify
    pulseaudio
    replaceVars
    symlinkJoin
    systemd
    ;
  inherit (lib) writeFileScriptBin;
  speaker-mute-toggle = writeFileScriptBin {
    name = "speaker-mute-toggle";
    replacements = {
      DEFAULT_SINK = null;
      bash = "${bash}/bin/bash";
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
      speaker-status = "${speaker-status}/bin/speaker-status";
    };
    src = ./speaker/speaker-mute-toggle.bash;
  };
  speaker-status = writeFileScriptBin (
    let
      color = "ffffff";
      size = 24;
      volume-high-icon = replaceVars ./speaker/speaker-volume-high.svg {
        inherit color size;
      };
      volume-low-icon = replaceVars ./speaker/speaker-volume-low.svg {
        inherit color size;
      };
      volume-med-icon = replaceVars ./speaker/speaker-volume-med.svg {
        inherit color size;
      };
      volume-mute-icon = replaceVars ./speaker/speaker-volume-mute.svg {
        inherit color size;
      };
    in
    {
      name = "speaker-status";
      replacements = {
        DEFAULT_SINK = null;
        bash = "${bash}/bin/bash";
        inherit
          volume-low-icon
          volume-med-icon
          volume-high-icon
          volume-mute-icon
          ;
        notify-send = "${libnotify}/bin/notify-send";
        pactl = "${pulseaudio}/bin/pactl";
      };
      src = ./speaker/speaker-status.bash;
    }
  );
  speaker-volume-down = writeFileScriptBin {
    name = "speaker-volume-down";
    replacements = {
      DEFAULT_SINK = null;
      bash = "${bash}/bin/bash";
      canberra-gtk-play = "${libcanberra-gtk3}/bin/canberra-gtk-play";
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
      speaker-status = "${speaker-status}/bin/speaker-status";
    };
    src = ./speaker/speaker-volume-down.bash;
  };
  speaker-volume-up = writeFileScriptBin {
    name = "speaker-volume-up";
    replacements = {
      DEFAULT_SINK = null;
      bash = "${bash}/bin/bash";
      canberra-gtk-play = "${libcanberra-gtk3}/bin/canberra-gtk-play";
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
      speaker-status = "${speaker-status}/bin/speaker-status";
    };
    src = ./speaker/speaker-volume-up.bash;
  };
in
symlinkJoin {
  name = "speaker";
  paths = [
    speaker-mute-toggle
    speaker-status
    speaker-volume-down
    speaker-volume-up
  ];
}
