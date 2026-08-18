# Guards the branch's core invariant: every user-facing lock trigger goes
# through `loginctl lock-session` -- which emits logind's Lock signal, bridged
# to lock.target -> gtklock by nixosModules/gtklock.nix (tests/gtklock.nix) --
# rather than invoking gtklock directly. (PR #294 shipped the bridge but left a
# trigger invoking gtklock directly, so it never reached the unified path; this
# check is what would have caught that.)
#
# swayidle's idle-timeout / before-sleep locks are the third trigger and are
# covered separately in tests/sway-idle.nix.
{ self, nixpkgs, ... }:
let
  pkgs = nixpkgs.extend self.overlays.thoughtfull;
  inherit (pkgs.thoughtfull) power-menu;
  waybarConfig = ../nixosModules/sway/waybar/config.jsonc;
in
pkgs.runCommand "lock-triggers-test" { } ''
  fail() { echo "lock-triggers test failed: $1" >&2; exit 1; }

  # power-menu's Lock entry routes through `loginctl lock-session`, not gtklock.
  pm="${power-menu}/bin/power-menu"
  grep -qE '/bin/loginctl lock-session' "$pm" \
    || fail "power-menu Lock does not route through 'loginctl lock-session'"
  ! grep -q gtklock "$pm" \
    || fail "power-menu still references gtklock directly"

  # waybar's lock button does the same.
  grep -q 'loginctl lock-session' ${waybarConfig} \
    || fail "waybar custom/lock does not route through 'loginctl lock-session'"

  touch "$out"
''
