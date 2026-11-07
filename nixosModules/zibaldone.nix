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
