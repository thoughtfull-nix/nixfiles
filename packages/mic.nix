{ lib, pkgs, ... }:
let
  inherit (pkgs)
    libcanberra-gtk3
    libnotify
    pulseaudio
    replaceVars
    symlinkJoin
    systemd
    ;
  inherit (lib) writeFileScriptBin;
  mic-mute-toggle = writeFileScriptBin {
    name = "mic-mute-toggle";
    replacements = {
      DEFAULT_SOURCE = null;
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
      mic-status = "${mic-status}/bin/mic-status";
    };
    src = ./mic/mic-mute-toggle.bash;
  };
  mic-status = writeFileScriptBin (
    let
      color = "ffffff";
      size = 24;
      volume-high-icon = replaceVars ./mic/mic-volume-high.svg {
        inherit color size;
      };
      volume-low-icon = replaceVars ./mic/mic-volume-low.svg {
        inherit color size;
      };
      volume-med-icon = replaceVars ./mic/mic-volume-med.svg {
        inherit color size;
      };
      volume-mute-icon = replaceVars ./mic/mic-volume-mute.svg {
        inherit color size;
      };
    in
    {
      name = "mic-status";
      replacements = {
        DEFAULT_SOURCE = null;
        inherit
          volume-low-icon
          volume-med-icon
          volume-high-icon
          volume-mute-icon
          ;
        notify-send = "${libnotify}/bin/notify-send";
        pactl = "${pulseaudio}/bin/pactl";
      };
      src = ./mic/mic-status.bash;
    }
  );
  mic-volume-down = writeFileScriptBin {
    name = "mic-volume-down";
    replacements = {
      DEFAULT_SOURCE = null;
      canberra-gtk-play = "${libcanberra-gtk3}/bin/canberra-gtk-play";
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
      mic-status = "${mic-status}/bin/mic-status";
    };
    src = ./mic/mic-volume-down.bash;
  };
  mic-volume-up = writeFileScriptBin {
    name = "mic-volume-up";
    replacements = {
      DEFAULT_SOURCE = null;
      canberra-gtk-play = "${libcanberra-gtk3}/bin/canberra-gtk-play";
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
      mic-status = "${mic-status}/bin/mic-status";
    };
    src = ./mic/mic-volume-up.bash;
  };
in
symlinkJoin {
  name = "mic";
  paths = [
    mic-mute-toggle
    mic-status
    mic-volume-down
    mic-volume-up
  ];
}
