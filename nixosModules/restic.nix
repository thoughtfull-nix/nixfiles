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
    prune
    repositoryFile
    ;
  inherit (lib)
    concatStringsSep
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    optional
    optionalAttrs
    ;
  inherit (lib.types)
    listOf
    nullOr
    path
    str
    ;
  pruneOptions = [
    "--retry-lock 1h"
    "--keep-hourly 24"
    "--keep-daily 7"
    "--keep-weekly 5"
    "--keep-monthly 12"
    "--keep-yearly 75"
    # restic's default --max-unused 5% makes forget/prune repack nearly every
    # run (each expiring snapshot pushes waste back over the ceiling), which is
    # expensive against S3: repacking downloads whole packs to reclaim a few
    # percent of garbage, at roughly 4x the $/GB of just leaving that garbage in
    # place as storage. 20% lets waste build up between repacks instead.
    "--max-unused 20%"
  ];
  # Prune garbage-collects the whole (shared) repository, so it should run from
  # exactly one always-on host, not on every host's hourly backup. Everything
  # that touches the repo before sleep is stopped to avoid an orphaned lock.
  stopServices = [
    "restic-backups-default.service"
  ]
  ++ optional prune.enable "restic-backups-prune.service";
in
{
  config = mkIf enable {
    age.secrets = {
      resticEnvironment.file = environmentFile;
      resticPassword.file = passwordFile;
      resticRepository.file = repositoryFile;
    };
    services.restic.backups = {
      default = {
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
        repositoryFile = resticRepository.path;
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
        };
      };
    }
    // optionalAttrs prune.enable {
      # A prune-only job: with no paths (and no dynamicFilesFrom/command) the
      # upstream module runs `forget --prune` without a preceding backup. A
      # single repository-wide forget applies retention to every host's
      # snapshots, so other hosts only need to back up.
      prune = {
        environmentFile = resticEnvironment.path;
        passwordFile = resticPassword.path;
        paths = [ ];
        pruneOpts = pruneOptions;
        repositoryFile = resticRepository.path;
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };
    # restic exits 130 when terminated by SIGINT/SIGTERM (e.g. by
    # restic-stop-before-sleep below); don't treat that as a failure.
    systemd.services = {
      restic-backups-default.serviceConfig.SuccessExitStatus = mkDefault [ 130 ];
      restic-stop-before-sleep = {
        description = "Stop restic before sleep to avoid an orphaned repo lock breaking backups on other hosts";
        before = [ "sleep.target" ];
        wantedBy = [ "sleep.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.systemd}/bin/systemctl stop ${concatStringsSep " " stopServices}";
        };
      };
    }
    // optionalAttrs prune.enable {
      restic-backups-prune.serviceConfig.SuccessExitStatus = mkDefault [ 130 ];
    };
    # This daily prune is the only thing garbage-collecting the shared repo, so
    # a silent failure would quietly reintroduce unbounded growth: alert on it.
    thoughtfull.monitoring.services = optional prune.enable "restic-backups-prune";
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
    prune.enable = mkEnableOption ''
      a daily repository-wide restic {command}`forget --prune` job. Prune
      garbage-collects the whole repository, so enable it on exactly one
      always-on host; every other host only backs up hourly. This keeps every
      host from running the expensive repack against the shared repository every
      hour
    '';
    repositoryFile = mkOption {
      default = ../nixosConfigurations/shared/secrets/restic-repository.age;
      description = ''
        Path to the age encrypted file containing the repository location to backup to.
      '';
      type = nullOr path;
    };
  };
}
