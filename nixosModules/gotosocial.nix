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

    services = {
      gotosocial = {
        environmentFile = mkIf hasEnvironmentFile config.age.secrets.gotosocial-environment.path;
        openFirewall = mkDefault false;
        settings = {
          account-domain = mkDefault "thoughtfull.systems";
          advanced-rate-limit-requests = mkDefault 1000;
          application-name = mkOverride 900 "Thoughtfull Systems";
          bind-address = mkOverride 900 "localhost";
          cache.memory-target = mkDefault "50MiB";
          db-max-open-conns-multiplier = mkDefault 1;
          host = mkDefault "social.thoughtfull.systems";
          instance-languages = mkDefault [ "en" ];
          landing-page-user = mkDefault "technosophist";
          letsencrypt-enabled = mkDefault false;
          port = mkOverride 900 8002;
          protocol = mkOverride 900 "https";
        };
        setupPostgresqlDB = mkDefault true;
      };
      postgresqlBackup.databases = [ "gotosocial" ];
    };
    thoughtfull = {
      impermanence.directories = [
        {
          directory = "/var/lib/gotosocial";
          user = "gotosocial";
          group = "gotosocial";
          mode = "0750";
        }
      ];
      monitoring.services = [ "gotosocial" ];
    };
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
