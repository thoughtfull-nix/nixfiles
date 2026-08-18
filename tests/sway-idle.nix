# Lightweight nix eval check (not a nixosTest/VM boot) for sway/idle.nix's
# swayidle config: the default (desktop / AC) idle policy -- lock via `loginctl
# lock-session` (feeding the unified lock.target path in nixosModules/gtklock.nix,
# tests/gtklock.nix) rather than invoking gtklock directly, lock at 15m, blank at
# 20m, both timeouts configurable.
#
# The laptop battery override (shorter timings + fire-time power checks +
# suspend) lives in nixosModules/laptop.nix and is checked in tests/laptop.nix.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
        ../nixosModules/swayidle.nix
        ../nixosModules/sway/idle.nix
        { programs.sway.enable = true; }
        extraModule
      ];
    };

  defaultConfig = (mkEval { }).config.programs.swayidle.extraConfig;

  customizedConfig =
    (mkEval {
      thoughtfull.programs.sway.idle = {
        lockSeconds = 42;
        blankDelaySeconds = 8;
      };
    }).config.programs.swayidle.extraConfig;

  has = needle: haystack: lib.hasInfix needle haystack;

  checks = [
    {
      name = "idle lock routes through loginctl lock-session, not gtklock directly";
      ok = has "loginctl lock-session" defaultConfig && !(has "gtklock" defaultConfig);
    }
    {
      name = "screen locks after 15 minutes of inactivity";
      ok = has "timeout 900 'loginctl lock-session'" defaultConfig;
    }
    {
      name = "screen blanks after 20 minutes (5 minutes after locking)";
      ok = has "timeout 1200 'swaymsg \"output * power off\"'" defaultConfig;
    }
    {
      name = "no swayidle before-sleep (systemd-lock-handler locks before sleep)";
      ok = !(has "before-sleep" defaultConfig);
    }
    {
      name = "lock and blank timeouts are configurable (blank = lock + delay)";
      ok =
        has "timeout 42 'loginctl lock-session'" customizedConfig
        && has "timeout 50 'swaymsg \"output * power off\"'" customizedConfig;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    sway-idle test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "sway-idle-test" { } "touch $out"
