# Lightweight nix eval check (not a nixosTest/VM boot) for system-pull.nix:
# verifying the timer schedule, the unit's ExecStart/X-StopOnRemoval/
# EnvironmentFile wiring, the nix.conf substituter/trusted-key wiring, and the
# generated script's credential handling (dotenvy scoping, no sourcing, no
# systemd-run, bucket/region/creds-path baked in).
#
# A VM boot was considered and rejected: none of the above depends on
# system-pull actually running -- every assertion here reads either plain
# config (timer/unit options, nix.conf settings) or the generated script's own
# text. Reading that text does realize the (tiny, dependency-free) script
# derivation via builtins.readFile, but that's a sub-second build, not a VM
# boot, and it's the same generated file a VM's `cat` would have read anyway.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  commonModules = [
    { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
    ../nixosModules/binary-cache.nix
    ../nixosModules/system-pull.nix
    stubs.ageSecrets
    stubs.graphicalEnable
  ];

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = commonModules ++ [ extraModule ];
    };

  # Credentials configured, default `enable` propagates to true.
  headless = mkEval (
    { pkgs, ... }:
    {
      thoughtfull.binaryCache.awsCredentialsFile = pkgs.writeText "fake-creds" "AWS_ACCESS_KEY_ID=x\nAWS_SECRET_ACCESS_KEY=y\n";
    }
  );
  graphical = mkEval (
    { pkgs, ... }:
    {
      thoughtfull.graphical.enable = true;
      thoughtfull.binaryCache.awsCredentialsFile = pkgs.writeText "fake-creds" "AWS_ACCESS_KEY_ID=x\nAWS_SECRET_ACCESS_KEY=y\n";
    }
  );
  # No credentials => systemPull default is false, no timer/service.
  noCredentials = mkEval { thoughtfull.binaryCache.awsCredentialsFile = null; };
  # NetworkManager explicitly enabled (e.g. hydor via graphical.nix): nm-online
  # is guaranteed to be installed, so the live connectivity check should apply.
  # `headless` deliberately leaves NetworkManager off (its default), standing
  # in for hosts like tislit -- rpi4.nix forces networkmanager.enable = false
  # and useNetworkd = true, so nm-online is never installed there and
  # referencing it unconditionally would make every system-pull run fail.
  networkManager = mkEval (
    { pkgs, ... }:
    {
      networking.networkmanager.enable = true;
      thoughtfull.binaryCache.awsCredentialsFile = pkgs.writeText "fake-creds" "AWS_ACCESS_KEY_ID=x\nAWS_SECRET_ACCESS_KEY=y\n";
    }
  );

  headlessUnit = headless.config.systemd.services.system-pull;
  headlessTimer = headless.config.systemd.timers.system-pull.timerConfig;
  graphicalTimer = graphical.config.systemd.timers.system-pull.timerConfig;
  networkManagerUnit = networkManager.config.systemd.services.system-pull;

  systemPullPkg = lib.head (
    builtins.filter (p: (p.name or "") == "system-pull") headless.config.environment.systemPackages
  );
  script = builtins.readFile "${systemPullPkg}/bin/system-pull";
  # Strip comment lines so checks aren't fooled by prose (mirrors the original
  # VM test, which stripped comments from the same generated script).
  code = lib.concatStringsSep "\n" (
    builtins.filter (line: builtins.match "[[:space:]]*#.*" line == null) (lib.splitString "\n" script)
  );
  codeLines = lib.splitString "\n" code;
  realiseLine = lib.findFirst (l: lib.hasInfix "--realise" l) "" codeLines;
  switchLine = lib.findFirst (l: lib.hasInfix "switch-to-configuration" l) "" codeLines;

  checks = [
    {
      name = "headless default: timer fires at 3am";
      ok = headlessTimer.OnCalendar == "*-*-* 03:00:00";
    }
    {
      name = "headless default: 15min randomized delay, persistent";
      ok = headlessTimer.RandomizedDelaySec == "15min" && headlessTimer.Persistent;
    }
    {
      name = "graphical default: timer fires at noon";
      ok = graphicalTimer.OnCalendar == "*-*-* 12:00:00";
    }
    {
      name = "service invokes system-pull with no arguments, no store path baked in";
      ok = headlessUnit.serviceConfig.ExecStart == "/run/current-system/sw/bin/system-pull";
    }
    {
      # network-online.target is satisfied once at boot by
      # NetworkManager-wait-online.service (Type=oneshot, RemainAfterExit=yes)
      # and never re-checked. On a laptop that suspends, the target stays
      # "active" straight through sleep/resume, so After=/Wants= on it is a
      # no-op after boot: if the daily timer's Persistent= catch-up fires
      # right after wake (Wi-Fi not yet reassociated), nothing blocks it. A
      # live nm-online check (no -s, which only checks the boot-time startup
      # milestone) re-verifies connectivity on every start instead -- but only
      # where NetworkManager is actually enabled, so nm-online is guaranteed
      # to be installed.
      name = "NetworkManager enabled: waits for a live connectivity check before pulling, not just the stale network-online.target";
      ok =
        networkManagerUnit.serviceConfig.ExecStartPre == "/run/current-system/sw/bin/nm-online -q -t 60";
    }
    {
      name = "NetworkManager disabled (e.g. rpi4/networkd hosts): no ExecStartPre referencing nm-online, which wouldn't be installed";
      ok = !(headlessUnit.serviceConfig ? ExecStartPre);
    }
    {
      name = "AWS credentials must not be loaded into system-pull.service's environment";
      ok = !(headlessUnit.serviceConfig ? EnvironmentFile);
    }
    {
      name = "service opts out of stop-on-removal so an in-flight switch survives";
      ok = headlessUnit.unitConfig."X-StopOnRemoval" == false;
    }
    {
      name = "switch-to-configuration runs in-process, not via systemd-run";
      ok = lib.hasInfix "switch-to-configuration" code && !(lib.hasInfix "systemd-run" code);
    }
    {
      name = "credentials are loaded scoped via dotenvy, not sourced";
      ok = lib.hasInfix "dotenvy -f" code && !(lib.hasInfix "source " code);
    }
    {
      name = "the closure is realised with credentials scoped to that command";
      ok = lib.hasInfix "dotenvy -f" realiseLine;
    }
    {
      name = "switch-to-configuration does not receive the AWS credentials";
      ok = !(lib.hasInfix "dotenvy" switchLine);
    }
    {
      name = "bucket, region, and credentials path are baked into the script";
      ok =
        lib.hasInfix ''bucket="thoughtfull-nix-cache"'' script
        && lib.hasInfix ''region="us-east-1"'' script
        && lib.hasInfix ''creds_file="/run/agenix/nix-cache-credentials"'' script;
    }
    {
      name = "nix.conf gets s3:// substituter and trusted public key";
      ok =
        lib.elem "s3://thoughtfull-nix-cache?region=us-east-1" headless.config.nix.settings.extra-substituters
        && lib.any (
          k: lib.hasPrefix "nix-cache.thoughtfull.systems-1:" k
        ) headless.config.nix.settings.extra-trusted-public-keys;
    }
    {
      name = "no credentials: no system-pull timer or service";
      ok =
        !(noCredentials.config.systemd.timers ? system-pull)
        && !(noCredentials.config.systemd.services ? system-pull);
    }
    {
      name = "no credentials: no s3 substituter";
      ok =
        !(lib.any (s: lib.hasInfix "s3://" s) (
          noCredentials.config.nix.settings.extra-substituters or [ ]
        ));
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    system-pull test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}

    generated script:
    ${script}
  ''
else
  nixpkgs.runCommand "system-pull-test" { } "touch $out"
