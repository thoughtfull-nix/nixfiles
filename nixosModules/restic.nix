{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.age.secrets) resticEnvironment resticPassword resticRepository;
  inherit (config.services.restic.thoughtfull)
    enable
    environmentFile
    passwordFile
    repositoryFile
    ;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    ;
  inherit (lib.types)
    listOf
    nullOr
    path
    str
    ;
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
      ]
      ++ config.services.restic.thoughtfull.exclude;
      extraBackupArgs = [
        "--no-scan"
        "--retry-lock 1h"
      ];
      passwordFile = resticPassword.path;
      paths = config.services.restic.thoughtfull.paths;
      pruneOpts = [
        "--retry-lock 1h"
        "--keep-hourly 24"
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 75"
        # restic's default --max-unused 5% makes hourly forget/prune repack
        # nearly every run (each expiring hourly snapshot pushes waste back
        # over the ceiling), which is expensive against S3: repacking
        # downloads whole packs to reclaim a few percent of garbage, at
        # roughly 4x the $/GB of just leaving that garbage in place as
        # storage. 20% lets waste build up between repacks instead.
        "--max-unused 20%"
      ];
      repositoryFile = resticRepository.path;
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };
    # restic exits 130 when terminated by SIGINT/SIGTERM (e.g. by
    # restic-stop-before-sleep below); don't treat that as a failure.
    systemd.services.restic-backups-default.serviceConfig.SuccessExitStatus = mkDefault [ 130 ];
    systemd.services.restic-stop-before-sleep = {
      description = "Stop restic backup before sleep to avoid an orphaned repo lock breaking backups on other hosts";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl stop restic-backups-default.service";
      };
    };
  };
  options.services.restic.thoughtfull = {
    enable = mkEnableOption "restic";
    environmentFile = mkOption {
      default = ../nixosConfigurations/shared/secrets/restic-environment.age;
      description = ''
        age encrypted file containing the credentials to access the repository, in the format of an
        EnvironmentFile as described by {manpage}systemd.exec(5)
      '';
      type = nullOr path;
    };
    exclude = mkOption {
      default = [ ];
      description = ''
        Restic exclude patterns to append to the default backup's hardcoded cache-directory
        excludes. Other modules (for example thoughtfull.impermanence) contribute to this list.
      '';
      type = listOf str;
    };
    paths = mkOption {
      default = [ ];
      description = ''
        Paths for the default backup to back up. Other modules (for example
        thoughtfull.impermanence) contribute to this list.
      '';
      type = listOf str;
    };
    passwordFile = mkOption {
      default = ../nixosConfigurations/shared/secrets/restic-password.age;
      description = "Read the repository password from an age encrypted file.";
      type = nullOr path;
    };
    repositoryFile = mkOption {
      default = ../nixosConfigurations/shared/secrets/restic-repository.age;
      description = ''
        Path to the age encrypted file containing the repository location to backup to.
      '';
      type = nullOr path;
    };
  };
}
