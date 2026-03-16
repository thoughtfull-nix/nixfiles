{
  config,
  lib,
  pkgs,
  thoughtfull,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.thoughtfull.programs.dictation;

  # Whisper model variants with their URLs and hashes
  modelVariants = {
    tiny = {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin";
      sha256 = "sha256-7OuKVWLzFAUQz6f1Fy8AgQrGCdGTj+NGIy+k5fQdOOk=";
    };
    base = {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin";
      sha256 = "sha256-oDd5yG3zMjB19eeWyyzlAp8A7Ihp7uP9+4l6/jbG0AI=";
    };
    small = {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin";
      sha256 = "sha256-Ke+tTsMO2SMwWrEZjCQg5271uLqoLMqBo/bBDIPsPgk=";
    };
    medium = {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin";
      sha256 = "sha256-VcKePln1pr8yWILHl0fz0W9WfoxrP9pGmHZUDRXGI1s=";
    };
    large = {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin";
      sha256 = "sha256-1ERrcCW0xG2Bl/kcHXXL7teRClV8EQBdZhJHX3GJZzM=";
    };
  };

  modelFile = pkgs.fetchurl modelVariants.${cfg.modelVariant};

  dictation = thoughtfull.pkgs.dictation.override {
    inherit modelFile;
  };
in
{
  config = mkIf cfg.enable {
    environment = {
      etc."sway/config.d/dictation.conf".text = mkIf sway.enable ''
        bindsym --no-repeat Shift+Space exec dictation start
        bindsym --release Shift+Space exec dictation stop
      '';
      systemPackages = [ dictation ];
    };
  };
  options.thoughtfull.programs.dictation = {
    enable = mkEnableOption "speech dictation with whisper-cpp and wtype";
    modelVariant = mkOption {
      default = "base";
      description = ''
        Whisper model variant to use for speech recognition.
        Available variants (in order of size/accuracy):
        - tiny: Fastest, least accurate
        - base: Good balance of speed and accuracy
        - small: Better accuracy, slower
        - medium: High accuracy, slower
        - large: Best accuracy, slowest
      '';
      type = types.enum [ "tiny" "base" "small" "medium" "large" ];
    };
  };
}
