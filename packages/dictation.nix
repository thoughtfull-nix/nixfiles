{ lib, pkgs, ... }:
let
  inherit (pkgs.lib) makeOverridable;
  inherit (lib) writeFileScriptBin;
in
makeOverridable
  (
    {
      libnotify,
      modelFile ? null,
      sox,
      whisper-cpp,
      wtype,
    }:
    writeFileScriptBin {
      name = "dictation";
      replacements = {
        cancel-sound = ./dictation/cancel.wav;
        model = toString modelFile;
        notify-send = "${libnotify}/bin/notify-send";
        play = "${sox}/bin/play";
        recbin = "${sox}/bin/rec";
        start-sound = ./dictation/start.wav;
        whisper = "${whisper-cpp}/bin/whisper-cli";
        wtype = "${wtype}/bin/wtype";
      };
      src = ./dictation/dictation.bash;
    }
  )
  {
    inherit (pkgs)
      libnotify
      whisper-cpp
      sox
      wtype
      ;
  }
