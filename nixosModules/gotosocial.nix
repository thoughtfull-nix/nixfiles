{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    mkOverride
    types
    ;
  cfg = config.thoughtfull.gotosocial;
  gotosocial = config.services.gotosocial;
  hasEnvironmentFile = cfg.age.environmentFile != null;
in
{
  config = mkIf gotosocial.enable {
    age.secrets.gotosocial-environment = mkIf hasEnvironmentFile {
      file = cfg.age.environmentFile;
      owner = "gotosocial";
    };

    services.gotosocial = {
      environmentFile = mkIf hasEnvironmentFile config.age.secrets.gotosocial-environment.path;
      openFirewall = mkDefault false;
      setupPostgresqlDB = mkDefault true;
      settings = {
        account-domain = mkOverride 900 "thoughtfull.systems";
        advanced-rate-limit-requests = mkOverride 900 1000;
        application-name = mkOverride 900 "Thoughtfull Systems";
        bind-address = mkOverride 900 "localhost";
        cache.memory-target = mkOverride 900 "50MiB";
        db-max-open-conns-multiplier = mkOverride 900 1;
        host = mkOverride 900 "social.thoughtfull.systems";
        instance-languages = mkOverride 900 [ "en" ];
        landing-page-user = mkOverride 900 "technosophist";
        letsencrypt-enabled = mkOverride 900 false;
        port = mkOverride 900 8002;
        protocol = mkOverride 900 "https";
      };
    };
    services.postgresqlBackup.databases = [ "gotosocial" ];
    thoughtfull.impermanence.directories = [
      {
        directory = "/var/lib/gotosocial";
        user = "gotosocial";
        group = "gotosocial";
        mode = "0750";
      }
      {
        # Persist the live database so it survives the stateless root, but keep
        # it OUT of restic: a file-level copy of a running datadir isn't
        # crash-consistent. The hourly pg_dump above is the real backup.
        directory = "/var/lib/postgresql";
        user = "postgres";
        group = "postgres";
        mode = "0700";
        backup = false;
      }
    ];
    thoughtfull.monitoring.services = [ "gotosocial" ];
  };
  options.thoughtfull.gotosocial.age.environmentFile = mkOption {
    type = types.nullOr types.path;
    default = null;
    description = ''
      age-encrypted `EnvironmentFile` (systemd.exec(5) format) holding
      GoToSocial's sensitive settings as `GTS_*` environment variables (e.g.
      SMTP or OIDC credentials). Decrypted for, and owned by, the gotosocial
      user. May be left null for an instance with no such secrets.
    '';
  };
}
