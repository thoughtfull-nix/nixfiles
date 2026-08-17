# Lightweight nix eval check (not a nixosTest/VM boot) for gtklock.nix's
# lock.target wiring: making logind's Lock D-Bus signal -- what `loginctl
# lock-session` sends, and also what HandleLidSwitch(ExternalPower)=lock in
# nixosModules/laptop.nix triggers -- actually show the lock screen.
#
# A VM boot was considered and rejected: every assertion here is a
# presence/value check on rendered config (systemd-lock-handler.enable,
# systemd.user.services), which pure evaluation already answers, matching the
# pattern in tests/kanshi.nix.
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
        ../nixosModules/gtklock.nix
        extraModule
      ];
    };

  # programs.gtklock.enable defaults to false upstream, and gtklock.nix
  # itself doesn't turn it on (sway.nix does, via `programs.gtklock.enable =
  # mkDefault sway.enable`) -- so the "disabled" case is just gtklock.nix
  # evaluated on its own.
  disabled = mkEval { };
  enabled = mkEval { programs.gtklock.enable = true; };

  checks = [
    {
      name = "disabled: systemd-lock-handler is not enabled";
      ok = !disabled.config.services.systemd-lock-handler.enable;
    }
    {
      name = "disabled: no lock.target service is installed";
      ok = !(disabled.config.systemd.user.services ? gtklock-session-lock);
    }
    {
      name = "enabled: systemd-lock-handler bridges logind's Lock signal to lock.target";
      ok = enabled.config.services.systemd-lock-handler.enable;
    }
    {
      name = "enabled: a user service locks the screen when lock.target is reached, and reports back when unlocked";
      ok =
        let
          svc = enabled.config.systemd.user.services.gtklock-session-lock;
        in
        lib.elem "lock.target" svc.wantedBy
        && lib.elem "lock.target" svc.partOf
        && lib.elem "sway-session.target" svc.after
        && lib.elem "sway-session.target" svc.bindsTo
        && lib.elem "unlock.target" svc.onSuccess;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    gtklock test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "gtklock-test" { } "touch $out"
