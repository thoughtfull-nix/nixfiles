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
        # `builtins.path` forces an independent, content-addressed copy of just this file into the
        # store -- without it, this path literal instead resolves to a subpath of the flake's own
        # whole-source checkout, which is never registered as a declared input anywhere it gets
        # substituted in as text, so the built script's `source`-relative reference ends up
        # pointing at a path absent from the package's actual runtime closure on any machine that
        # doesn't separately already have this flake's source in its store.
        cancel-sound = builtins.path {
          path = ./dictation/cancel.wav;
          name = "cancel.wav";
        };
        model = toString modelFile;
        notify-send = "${libnotify}/bin/notify-send";
        play = "${sox}/bin/play";
        recbin = "${sox}/bin/rec";
        start-sound = builtins.path {
          path = ./dictation/start.wav;
          name = "start.wav";
        };
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
