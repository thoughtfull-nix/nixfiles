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
    mkDefault
    mkIf
    mkOption
    types
    ;
  hasCredentials = binaryCache.enable && binaryCache.awsCredentialsFile != null;
  # Bake the host's bucket, region, and credentials path into the script so it
  # runs with no arguments.
  system-pull = pkgs.thoughtfull.system-pull.override {
    inherit (binaryCache) bucket region;
    credentialsFile = config.age.secrets.nix-cache-credentials.path;
  };
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

    environment.systemPackages = [ system-pull ];

    systemd.services.system-pull = {
      description = mkDefault "Pull the latest system closure from the binary cache";
      # network-online.target is satisfied once at boot by
      # NetworkManager-wait-online.service (Type=oneshot, RemainAfterExit=yes)
      # and never re-checked afterwards. On a laptop that suspends, the target
      # stays "active" straight through sleep/resume, so this ordering is a
      # no-op after boot: if the daily timer's Persistent= catch-up run fires
      # right on wake (Wi-Fi not yet reassociated), nothing here blocks it.
      # Kept anyway because it is still correct at boot; the live check below
      # (ExecStartPre) is what actually guards against the stale-target case.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      restartIfChanged = mkDefault false;
      # Keep the running instance alive if a pulled generation removes this
      # unit: otherwise activation would stop it (X-StopOnRemoval defaults to
      # true) and kill the switch it is running in-process.
      unitConfig.X-StopOnRemoval = mkDefault false;
      serviceConfig = {
        Type = mkDefault "oneshot";
        User = mkDefault "root";
        # Deliberately no EnvironmentFile: the AWS credentials are only needed
        # to fetch the pointer and realise the closure, so the script loads
        # them (via dotenvy) scoped to just those two commands. Putting them in
        # the unit environment would expose them to switch-to-configuration and
        # every activation script it runs in-process. The realise carries the
        # credentials itself because system-pull runs as root, whose `auto`
        # store realises in-process rather than through nix-daemon, so the
        # daemon's own EnvironmentFile (see binary-cache.nix) does not apply.
        #
        # Reference system-pull through /run/current-system so the ExecStart is
        # a stable path that does not change on every rebuild. This keeps the
        # unit byte-identical across generations, so switch-to-configuration
        # leaves it untouched during activation and does not kill the in-flight
        # switch the script runs in-process. The script takes no arguments; its
        # bucket, region, and credentials path are baked in above.
        ExecStart = mkDefault "/run/current-system/sw/bin/system-pull";
        # Re-verify connectivity live on every start, since network-online.target
        # (see comment above) can be stale after resume. `nm-online` without -s
        # does a fresh check for an actual active connection (unlike -s, which
        # only checks the one-time boot startup milestone and would reproduce
        # the same staleness bug). Referenced through /run/current-system for
        # the same byte-identical-unit reason as ExecStart above.
        ExecStartPre = mkDefault "/run/current-system/sw/bin/nm-online -q -t 60";
      };
    };

    systemd.timers.system-pull = {
      description = mkDefault "Daily pull of the latest system closure";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = mkDefault cfg.dates;
        Persistent = mkDefault true;
        RandomizedDelaySec = mkDefault "15min";
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
