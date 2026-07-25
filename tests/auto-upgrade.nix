# Lightweight nix eval check (not a nixosTest/VM boot) for auto-upgrade.nix:
# verifying the timer schedule differs between graphical/headless hosts, and
# that reboot behavior (staged kernel update vs. immediate) follows suit.
#
# A VM boot was considered and rejected: upstream's system.autoUpgrade module
# stores the rendered upgrade script as a plain string in
# config.systemd.services.nixos-upgrade.script (before it becomes a wrapper
# derivation) -- reading it directly gives byte-for-byte the same text a VM's
# `systemctl cat` + `cat <ExecStart path>` would, without building or booting
# anything.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        ../nixosModules/auto-upgrade.nix
        stubs.graphicalEnable
        extraModule
      ];
    };

  graphical = mkEval {
    thoughtfull.graphical.enable = true;
    # Default is disabled; opt back in for this test node.
    system.autoUpgrade.enable = true;
  };
  headless = mkEval {
    # graphical.enable stays false
    system.autoUpgrade.enable = true;
  };
  # No override; should land on the module default of disabled.
  defaultDisabled = mkEval { };

  graphicalTimer = graphical.config.systemd.timers.nixos-upgrade.timerConfig;
  headlessTimer = headless.config.systemd.timers.nixos-upgrade.timerConfig;
  graphicalScript = graphical.config.systemd.services.nixos-upgrade.script;
  headlessScript = headless.config.systemd.services.nixos-upgrade.script;

  checks = [
    {
      name = "graphical default: timer fires at noon";
      ok = lib.elem "*-*-* 12:00:00" graphicalTimer.OnCalendar;
    }
    {
      name = "graphical default: 15min randomized delay";
      ok = graphicalTimer.RandomizedDelaySec == "15min";
    }
    {
      name = "graphical default: does not allow reboot";
      # When allowReboot=false, upstream emits `nixos-rebuild switch ...`
      # directly and never invokes `shutdown -r`.
      ok =
        !(lib.hasInfix "shutdown -r" graphicalScript)
        && !(lib.hasInfix "nixos-rebuild boot" graphicalScript);
    }
    {
      name = "headless default: timer fires at 3am";
      ok = lib.elem "*-*-* 03:00:00" headlessTimer.OnCalendar;
    }
    {
      name = "headless default: allows reboot";
      # When allowReboot=true, upstream's script first does `nixos-rebuild
      # boot ...` and conditionally `shutdown -r +1`.
      ok = lib.hasInfix "nixos-rebuild boot" headlessScript && lib.hasInfix "shutdown -r" headlessScript;
    }
    {
      name = "default flake URL points to thoughtfull-nix/nixfiles";
      ok = lib.hasInfix "--flake github:thoughtfull-nix/nixfiles" graphicalScript;
    }
    {
      name = "default: timer and service do not exist (build-and-push is the primary path)";
      ok =
        !(defaultDisabled.config.systemd.timers ? nixos-upgrade)
        && !(defaultDisabled.config.systemd.services ? nixos-upgrade);
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    auto-upgrade test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "auto-upgrade-test" { } "touch $out"
