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
      # Reachable only over the reverse tunnel; binds localhost, so no firewall
      # opening is wanted.
      openFirewall = mkDefault false;
      # Local PostgreSQL over the unix socket (peer auth), auto-provisioned.
      # Plain mkDefault: the upstream option default is lower priority still, so
      # this wins while staying host-overridable.
      setupPostgresqlDB = mkDefault true;
      # mkOverride 900 on the settings below: upstream defaults each of these via
      # mkDefault (priority 1000), so a plain mkDefault here would conflict; 900
      # wins over upstream while still yielding to a host's own override.
      settings = {
        account-domain = mkOverride 900 "thoughtfull.systems";
        application-name = mkOverride 900 "Thoughtfull Systems";
        bind-address = mkOverride 900 "localhost";
        cache.memory-target = mkOverride 900 "50MiB";
        db-max-open-conns-multiplier = mkOverride 900 1;
        # Served here, but account-domain (above) is the apex, so handles are
        # @user@thoughtfull.systems. The bastion redirects the apex's
        # .well-known/* discovery endpoints here to make that split work.
        host = mkOverride 900 "social.thoughtfull.systems";
        instance-languages = mkOverride 900 [ "en" ];
        landing-page-user = mkOverride 900 "technosophist";
        # TLS is terminated by the bastion's Caddy, not GoToSocial.
        letsencrypt-enabled = mkOverride 900 false;
        port = mkOverride 900 8002;
        protocol = mkOverride 900 "https";
      };
    };

    # The gotosocial DB is dumped hourly (see postgresql-backup.nix); the dump
    # is what restic backs up.
    services.postgresqlBackup.databases = [ "gotosocial" ];

    thoughtfull.impermanence.directories = [
      {
        # Media, instance keys, and other state -- persisted and backed up.
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
