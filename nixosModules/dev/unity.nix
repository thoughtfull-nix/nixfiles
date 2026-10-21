{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) dev;
  inherit (lib) mkEnableOption mkIf;
in
{
  config = mkIf (dev.enable && dev.unity.enable) {
    environment.systemPackages = [ pkgs.unityhub ];
    # Back up projects, Hub state, and licences, but not the re-downloadable editor installs
    # (Unity/Hub), per-project caches, or Asset Store downloads.
    thoughtfull.impermanence.user.directories = [
      {
        directory = "Unity";
        backupExclude = [
          "Hub"
          "**/Library"
          "**/Logs"
          "**/Temp"
        ];
      }
      {
        directory = ".config/unityhub";
        backupExclude = [
          "Cache"
          "Code Cache"
          "Crashpad"
          "DawnGraphiteCache"
          "DawnWebGPUCache"
          "GPUCache"
        ];
      }
      ".config/unity3d"
      {
        directory = ".local/share/unity3d";
        backupExclude = [ "Asset Store-5.x" ];
      }
    ];
  };
  options.thoughtfull.dev.unity.enable = mkEnableOption "Unity development configuration";
}
