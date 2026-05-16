{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  inherit (pkgs) gh;
  inherit (pkgs.unstable) claude-code;
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
