{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.thoughtfull.claudeDesktop;
  # buildFHSEnv's sandbox only links an allowlist of host /etc entries, which omits /etc/ssh
  claude-desktop-fhs = pkgs.claude-desktop-fhs.override {
    buildFHSEnv =
      args:
      pkgs.buildFHSEnv (
        args
        // {
          extraBwrapArgs = (args.extraBwrapArgs or [ ]) ++ [
            "--symlink /.host-etc/ssh /etc/ssh"
          ];
        }
      );
  };
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [
      claude-desktop-fhs
    ];
    thoughtfull.impermanence.user.directories = [
      ".config/Claude"
    ];
  };
  options.thoughtfull.claudeDesktop.enable = mkEnableOption "Claude Desktop";
}
