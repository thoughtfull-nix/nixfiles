{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.thoughtfull.claudeDesktop;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      claude-desktop-fhs
    ];
    thoughtfull.impermanence.user.directories = [
      ".config/Claude"
    ];
  };
  options.thoughtfull.claudeDesktop.enable = mkEnableOption "Claude Desktop";
}
