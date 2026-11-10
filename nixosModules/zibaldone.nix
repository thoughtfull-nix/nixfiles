{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.thoughtfull.programs.zibaldone;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.zibaldone ];
    programs.firefox = {
      nativeMessagingHosts.packages = [ pkgs.zibaldone ];
      policies.ExtensionSettings."web-clipper@zibaldone.thoughtfull.systems" = {
        installation_mode = "force_installed";
        install_url = "file://${pkgs.zib-web-clipper-signed}/zib-web-clipper.xpi";
      };
    };
    thoughtfull.impermanence.user.directories = [
      ".local/share/zibaldone"
      {
        # rebuildable search index
        directory = ".cache/zibaldone";
        backup = false;
      }
    ];
  };
  options.thoughtfull.programs.zibaldone.enable = mkEnableOption "zibaldone";
}
