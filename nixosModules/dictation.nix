{
  config,
  lib,
  thoughtfull,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.thoughtfull.programs.dictation;
  dictation = thoughtfull.pkgs.dictation.override {
    modelFile = cfg.modelFile;
  };
in
{
  config = mkIf cfg.enable {
    environment = {
      etc."sway/config.d/dictation.conf".text = mkIf sway.enable ''
        bindsym $mod+Shift+d exec dictation
      '';
      systemPackages = [ dictation ];
    };
  };
  options.thoughtfull.programs.dictation = {
    enable = mkEnableOption "speech dictation with whisper-cpp and wtype";
    modelFile = mkOption {
      default = null;
      description = ''
        Path to the whisper-cpp GGML model file for speech recognition.
        When null, the dictation script will show an error at runtime.

        Use `nix-prefetch-url` to obtain the correct hash for a model file.
        Example:
        ```nix
        pkgs.fetchurl {
          url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin";
          sha256 = ""; # fill in with: nix-prefetch-url <url>
        }
        ```
      '';
      type = types.nullOr types.path;
    };
  };
}
