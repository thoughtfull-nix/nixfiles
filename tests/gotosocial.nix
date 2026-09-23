# Lightweight nix eval check (not a VM boot) for nixosModules/gotosocial.nix.
#
# thoughtfull.gotosocial wraps the upstream services.gotosocial for this repo's
# impermanence + restic model. Under test is the eval-time wiring: the instance
# settings (host vs account-domain split, localhost:8002 behind a TLS-
# terminating proxy), local PostgreSQL provisioning, the agenix environment
# secret, and -- the crux -- persistence: /var/lib/gotosocial persisted AND
# backed up, /var/lib/postgresql persisted but EXCLUDED from restic (the hourly
# pg_dump is the real backup). Booting GoToSocial + PostgreSQL for real is
# upstream's concern; here we only assert the configuration this module derives.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  monitoringServicesStub =
    { lib, ... }:
    {
      options.thoughtfull.monitoring.services = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

  # Like stubs.ageSecrets but with the owner/group fields this module sets.
  ageSecretsStub =
    { lib, ... }:
    {
      options.age.secrets = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                file = lib.mkOption { type = lib.types.path; };
                owner = lib.mkOption {
                  type = lib.types.str;
                  default = "root";
                };
                group = lib.mkOption {
                  type = lib.types.str;
                  default = "root";
                };
                mode = lib.mkOption {
                  type = lib.types.str;
                  default = "0400";
                };
                path = lib.mkOption {
                  type = lib.types.str;
                  default = "/run/agenix/${name}";
                };
              };
            }
          )
        );
      };
    };

  mkEval =
    extraModule:
    (nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        ../nixosModules/gotosocial.nix
        stubs.impermanence
        monitoringServicesStub
        ageSecretsStub
        extraModule
      ];
    }).config;

  enabledEval = mkEval (
    { ... }:
    {
      services.gotosocial.enable = true;
      thoughtfull.gotosocial.age.environmentFile = builtins.toFile "gotosocial-environment" "GTS_SMTP_PASSWORD=test\n";
    }
  );

  disabledEval = mkEval ({ ... }: { });

  settings = enabledEval.services.gotosocial.settings;
  dirs = enabledEval.thoughtfull.impermanence.directories;
  gtsDir = lib.findFirst (d: (d.directory or null) == "/var/lib/gotosocial") null dirs;
  pgDir = lib.findFirst (d: (d.directory or null) == "/var/lib/postgresql") null dirs;
  secret = enabledEval.age.secrets.gotosocial-environment;

  checks = [
    {
      # Served at social.thoughtfull.systems but account-domain is the apex, so
      # handles are @user@thoughtfull.systems -- the split the bastion's apex
      # .well-known redirects exist to support.
      name = "enabled: host is social.thoughtfull.systems, account-domain is the apex";
      ok =
        settings.host == "social.thoughtfull.systems" && settings.account-domain == "thoughtfull.systems";
    }
    {
      name = "enabled: binds localhost:8002 (TLS terminated upstream by the proxy)";
      ok = settings.bind-address == "localhost" && settings.port == 8002 && settings.protocol == "https";
    }
    {
      name = "enabled: GoToSocial does not manage its own TLS";
      ok = settings.letsencrypt-enabled == false;
    }
    {
      name = "enabled: uses local PostgreSQL (auto-provisioned)";
      ok = enabledEval.services.gotosocial.setupPostgresqlDB;
    }
    {
      name = "enabled: does not open the firewall (reachable only via the tunnel)";
      ok = !enabledEval.services.gotosocial.openFirewall;
    }
    {
      name = "enabled: reads secrets from the agenix environment file";
      ok = enabledEval.services.gotosocial.environmentFile == "/run/agenix/gotosocial-environment";
    }
    {
      name = "enabled: the environment secret is owned by the gotosocial user";
      ok = secret.owner == "gotosocial";
    }
    {
      name = "enabled: /var/lib/gotosocial is persisted as gotosocial and backed up";
      ok = gtsDir != null && (gtsDir.user or null) == "gotosocial" && (gtsDir.backup or true);
    }
    {
      name = "enabled: /var/lib/postgresql is persisted but excluded from restic";
      ok = pgDir != null && (pgDir.backup or true) == false;
    }
    {
      name = "enabled: the gotosocial database is registered for pg_dump backup";
      ok = enabledEval.services.postgresqlBackup.databases == [ "gotosocial" ];
    }
    {
      name = "enabled: the gotosocial service is registered for failure monitoring";
      ok = lib.elem "gotosocial" enabledEval.thoughtfull.monitoring.services;
    }
    {
      name = "disabled: nothing persisted when GoToSocial is off";
      ok = disabledEval.thoughtfull.impermanence.directories == [ ];
    }
    {
      name = "disabled: nothing monitored when GoToSocial is off";
      ok = disabledEval.thoughtfull.monitoring.services == [ ];
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    gotosocial test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "gotosocial-test" { } "touch $out"
