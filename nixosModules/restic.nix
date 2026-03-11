{ config, lib, ... }:
let
  inherit (config.age.secrets) resticEnvironment resticPassword resticRepository;
  inherit (config.services.restic.thoughtfull)
    enable
    environmentFile
    passwordFile
    repositoryFile
    ;
  inherit (lib) mkEnableOption mkIf mkOption;
  inherit (lib.types) nullOr path;
in
{
  config = mkIf enable {
    age.secrets = {
      resticEnvironment.file = environmentFile;
      resticPassword.file = passwordFile;
      resticRepository.file = repositoryFile;
    };
    services.restic.backups.default = {
      environmentFile = resticEnvironment.path;
      exclude = [
        "/persistent/home/**/.cache"
        "/persistent/home/**/Cache"
        "/persistent/home/**/cache"
      ];
      extraBackupArgs = [
        "--no-scan"
        "--retry-lock 1h"
      ];
      passwordFile = resticPassword.path;
      paths = [ "/persistent" ];
      pruneOpts = [
        "--retry-lock 1h"
        "--keep-hourly 24"
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 75"
      ];
      repositoryFile = resticRepository.path;
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };
  };
  options.services.restic.thoughtfull = {
    enable = mkEnableOption "restic";
    environmentFile = mkOption {
      default = null;
      description = ''
        age encrypted file containing the credentials to access the repository, in the format of an
        EnvironmentFile as described by {manpage}systemd.exec(5)
      '';
      type = nullOr path;
    };
    passwordFile = mkOption {
      default = null;
      description = "Read the repository password from an age encrypted file.";
      type = nullOr path;
    };
    repositoryFile = mkOption {
      default = null;
      description = ''
        Path to the age encrypted file containing the repository location to backup to.
      '';
      type = nullOr path;
    };
  };
}
