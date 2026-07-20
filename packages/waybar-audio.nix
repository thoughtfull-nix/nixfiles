{ lib, pkgs, ... }:
let
  inherit (pkgs)
    bash
    fuzzel
    jq
    pulseaudio
    symlinkJoin
    systemd
    ;
  inherit (lib) writeFileScriptBin;
  waybar-audio-speaker = writeFileScriptBin {
    name = "waybar-audio-speaker";
    replacements = {
      bash = "${bash}/bin/bash";
      jq = "${jq}/bin/jq";
      pactl = "${pulseaudio}/bin/pactl";
    };
    src = ./waybar-audio/speaker-status.bash;
  };
  waybar-audio-speaker-menu = writeFileScriptBin {
    name = "waybar-audio-speaker-menu";
    replacements = {
      bash = "${bash}/bin/bash";
      fuzzel = "${fuzzel}/bin/fuzzel";
      jq = "${jq}/bin/jq";
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
    };
    src = ./waybar-audio/speaker-menu.bash;
  };
  waybar-audio-speaker-toggle = writeFileScriptBin {
    name = "waybar-audio-speaker-toggle";
    replacements = {
      DEFAULT_SINK = null;
      bash = "${bash}/bin/bash";
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
    };
    src = ./waybar-audio/speaker-toggle.bash;
  };
  waybar-audio-mic = writeFileScriptBin {
    name = "waybar-audio-mic";
    replacements = {
      bash = "${bash}/bin/bash";
      jq = "${jq}/bin/jq";
      pactl = "${pulseaudio}/bin/pactl";
    };
    src = ./waybar-audio/mic-status.bash;
  };
  waybar-audio-mic-menu = writeFileScriptBin {
    name = "waybar-audio-mic-menu";
    replacements = {
      bash = "${bash}/bin/bash";
      fuzzel = "${fuzzel}/bin/fuzzel";
      jq = "${jq}/bin/jq";
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
    };
    src = ./waybar-audio/mic-menu.bash;
  };
  waybar-audio-mic-toggle = writeFileScriptBin {
    name = "waybar-audio-mic-toggle";
    replacements = {
      DEFAULT_SOURCE = null;
      bash = "${bash}/bin/bash";
      pactl = "${pulseaudio}/bin/pactl";
      systemctl = "${systemd}/bin/systemctl";
    };
    src = ./waybar-audio/mic-toggle.bash;
  };
in
symlinkJoin {
  name = "waybar-audio";
  paths = [
    waybar-audio-mic
    waybar-audio-mic-menu
    waybar-audio-mic-toggle
    waybar-audio-speaker
    waybar-audio-speaker-menu
    waybar-audio-speaker-toggle
  ];
}
