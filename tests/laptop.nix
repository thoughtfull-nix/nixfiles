# Lightweight nix eval check (not a nixosTest/VM boot) for laptop.nix's
# lid-close power wiring:
#
#   - Closing the lid always locks the screen immediately, on AC or battery
#     alike (logind's HandleLidSwitch(ExternalPower) can only run one of a
#     fixed set of actions -- "lock" -- so AC vs. battery isn't
#     distinguishable at that point; see below for how that distinction is
#     made instead). Making "lock" actually show the lock screen is
#     nixosModules/gtklock.nix's job (tests/gtklock.nix), shared with
#     `loginctl lock-session`.
#   - On AC, staying locked never suspends -- long-running work (builds,
#     downloads, etc.) keeps going indefinitely.
#   - On battery, staying locked for a while suspends (the exact delay is a
#     tunable, not asserted on here). logind's Lock signal doesn't carry a
#     reason, so this fires from *any* lock while on battery (idle-timeout,
#     manual lock, or lid-close) -- not exclusively from closing the lid --
#     by design (see nixosModules/laptop.nix).
#
# A VM boot was considered and rejected: lid hardware and actual suspend
# behavior can't be exercised in a VM anyway -- every assertion here is a
# presence/value check on rendered config (logind settings,
# systemd.user.timers/services), which pure evaluation already answers,
# matching the pattern in tests/kanshi.nix.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  # programs.gtklock is a real nixpkgs module (nixos/modules/programs/wayland/
  # gtklock.nix), already included by nixosSystem's default module list -- no
  # stub needed, unlike e.g. thoughtfull.graphical.enable in tests/kanshi.nix.
  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
        ../nixosModules/laptop.nix
        extraModule
      ];
    };

  disabled = mkEval { };
  # thoughtfull.laptop.enable defaults to false

  enabledNoGtklock = mkEval { thoughtfull.laptop.enable = true; };

  enabledWithGtklock = mkEval {
    thoughtfull.laptop.enable = true;
    programs.gtklock.enable = true;
  };

  checks = [
    {
      name = "disabled: lid-switch handling is not touched";
      ok =
        !(disabled.config.services.logind.settings.Login ? HandleLidSwitch)
        && !(disabled.config.services.logind.settings.Login ? HandleLidSwitchExternalPower);
    }
    {
      name = "enabled: closing the lid locks rather than suspending, on AC or battery";
      ok =
        enabledNoGtklock.config.services.logind.settings.Login.HandleLidSwitch == "lock"
        && enabledNoGtklock.config.services.logind.settings.Login.HandleLidSwitchExternalPower == "lock";
    }
    {
      name = "enabled, no gtklock: there's no suspend timer (nothing drives lock.target)";
      ok =
        !(enabledNoGtklock.config.systemd.user.timers ? battery-lock-suspend)
        && !(enabledNoGtklock.config.systemd.user.services ? battery-lock-suspend);
    }
    {
      name = "enabled with gtklock: staying locked starts a countdown, torn down if unlocked first";
      ok =
        let
          timer = enabledWithGtklock.config.systemd.user.timers.battery-lock-suspend;
        in
        lib.elem "lock.target" timer.wantedBy
        && lib.elem "lock.target" timer.partOf
        # The exact delay is a tunable, not asserted on here -- just that one
        # is actually set.
        && timer.timerConfig ? OnActiveSec;
    }
    {
      name = "enabled with gtklock: the countdown only actually suspends if still on battery when it fires";
      ok =
        let
          svc = enabledWithGtklock.config.systemd.user.services.battery-lock-suspend;
        in
        svc.unitConfig.ConditionACPower == false && svc.serviceConfig.Type == "oneshot";
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    laptop test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "laptop-test" { } "touch $out"
