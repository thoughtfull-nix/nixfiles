{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) binaryCache graphical;
  cfg = config.thoughtfull.systemPull;
  inherit (lib)
    mkIf
    mkOption
    types
    ;
  hasCredentials = binaryCache.enable && binaryCache.awsCredentialsFile != null;
in
{
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = hasCredentials;
        message = ''
          thoughtfull.systemPull requires thoughtfull.binaryCache.enable to
          be true and thoughtfull.binaryCache.awsCredentialsFile to be set:
          the pull script needs the binary cache substituter to realise the
          system closure and the same AWS credentials to fetch the pointer
          file.
        '';
      }
    ];

    systemd.services.system-pull = {
      description = "Pull the latest system closure from the binary cache";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.thoughtfull.system-pull ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        EnvironmentFile = config.age.secrets.cache-aws-credentials.path;
        ExecStart = "${pkgs.thoughtfull.system-pull}/bin/system-pull ${binaryCache.bucket} ${binaryCache.region}";
      };
    };

    systemd.timers.system-pull = {
      description = "Daily pull of the latest system closure";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.dates;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };
  };

  options.thoughtfull.systemPull = {
    dates = mkOption {
      default = if graphical.enable then "*-*-* 12:00:00" else "*-*-* 03:00:00";
      defaultText = ''"*-*-* 12:00:00" if graphical.enable else "*-*-* 03:00:00"'';
      description = ''
        `OnCalendar` expression for the daily pull timer. CI publishes
        new closures around 02:00 UTC, so the headless default of 03:00
        gives the slowest aarch64 build time to finish.
      '';
      type = types.str;
    };
    enable = mkOption {
      default = hasCredentials;
      defaultText = "thoughtfull.binaryCache.enable && thoughtfull.binaryCache.awsCredentialsFile != null";
      description = ''
        Run `system-pull` daily to fetch the latest signed closure for
        this host from the binary cache and switch to it.

        Defaults to enabled whenever the binary cache is enabled and an
        `awsCredentialsFile` is configured — i.e. once the operator has
        committed the encrypted credentials file, every host turns this
        on automatically (opt-out per host).

        Installer/bootstrap images set this to `false` explicitly.
      '';
      type = types.bool;
    };
  };
}
