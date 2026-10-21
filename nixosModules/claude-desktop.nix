{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkDefault mkEnableOption mkIf;
  cfg = config.thoughtfull.claudeDesktop;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      bubblewrap
      claude-desktop
    ];
    # Claude Desktop downloads its own generic Linux Claude Code binaries
    programs.nix-ld.enable = mkDefault true;
    thoughtfull.impermanence.user.directories = [
      ".config/Claude"
    ];
  };
  options.thoughtfull.claudeDesktop.enable = mkEnableOption "Claude Desktop";
}
