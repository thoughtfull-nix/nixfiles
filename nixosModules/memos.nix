{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkDefault mkIf;
  memos = config.services.memos;
in
{
  config = mkIf memos.enable {
    services = {
      memos = {
        package = pkgs.unstable.memos;
        settings = {
          MEMOS_MODE = mkDefault "prod";
          MEMOS_ADDR = mkDefault "127.0.0.1";
          MEMOS_PORT = mkDefault "5230";
          MEMOS_DATA = mkDefault memos.dataDir;
          MEMOS_DRIVER = mkDefault "postgres";
          # Peer-authenticated local socket: the memos system user maps to the
          # like-named PostgreSQL role, so no password or secret is needed.
          MEMOS_DSN = mkDefault "user=memos host=/run/postgresql dbname=memos sslmode=disable";
          # Public origin: TLS is terminated by Caddy on the buna bastion, which
          # reverse-proxies this host over the SSH tunnel.
          MEMOS_INSTANCE_URL = mkDefault "https://notes.thoughtfull.systems";
        };
      };

      postgresql = {
        enable = mkDefault true;
        ensureDatabases = [ "memos" ];
        ensureUsers = [
          {
            name = "memos";
            ensureDBOwnership = true;
          }
        ];
      };
      postgresqlBackup.databases = [ "memos" ];
    };

    # postgresql-setup.service runs the ensureUsers/ensureDatabases
    # provisioning; it is oneshot + RemainAfterExit and ordered after
    # postgresql.service, so waiting on it guarantees the memos role and
    # database exist. Ordering only after postgresql.service (or the
    # postgresql.target, which imposes no ordering on its members) races the
    # setup and memos fails its first migration with "role memos does not exist".
    systemd.services.memos = {
      after = [ "postgresql-setup.service" ];
      wants = [ "postgresql-setup.service" ];
    };

    thoughtfull = {
      impermanence.directories = [
        {
          # Uploaded assets and other local state; the database lives in
          # PostgreSQL. Small and safe to snapshot at the file level.
          directory = "/var/lib/memos";
          user = "memos";
          group = "memos";
          mode = "0750";
        }
      ];
      monitoring.services = [ "memos" ];
    };
  };
}
