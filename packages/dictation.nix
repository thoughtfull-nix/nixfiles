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
      openai-whisper-cpp,
      sox,
      wtype,
    }:
    writeFileScriptBin {
      name = "dictation";
      replacements = {
        model = toString modelFile;
        notify-send = "${libnotify}/bin/notify-send";
        rec = "${sox}/bin/rec";
        whisper-cpp = "${openai-whisper-cpp}/bin/whisper-cpp";
        wtype = "${wtype}/bin/wtype";
      };
      src = ./dictation/dictation.bash;
    }
  )
  {
    inherit (pkgs)
      libnotify
      openai-whisper-cpp
      sox
      wtype
      ;
  }
