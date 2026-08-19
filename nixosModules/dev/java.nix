{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) dev;
  inherit (lib) mkDefault mkEnableOption mkIf;
in
{
  config = mkIf (dev.enable && dev.java.enable) {
    programs.java.package = mkDefault pkgs.javaPackages.compiler.temurin-bin.jdk-25;
    # Persist the Maven local repository across boots so downloaded artifacts survive a reboot,
    # but keep it out of restic backups (backup = false): it is a disposable cache that Maven
    # re-downloads on demand.
    thoughtfull.impermanence.user.directories = [
      {
        directory = ".m2/repository";
        backup = false;
      }
    ];
  };
  options.thoughtfull.dev.java.enable = (mkEnableOption "Java development configuration") // {
    default = true;
  };
}
