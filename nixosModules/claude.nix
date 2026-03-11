{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  inherit (pkgs) claude-code gh;
  cfg = config.thoughtfull.claude;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [
      claude-code
      gh
    ];
    thoughtfull.impermanence.user = {
      directories = [
        ".claude"
        ".config/gh"
      ];
      files = [ ".claude.json" ];
    };
  };
  options.thoughtfull.claude.enable = mkEnableOption "claude configuration";
}
