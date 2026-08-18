#!@bash@
set -euo pipefail

# sway bindswitch handler for the laptop lid.
#   on  -- lid closed: if docked, switch to the external monitor by disabling the
#          laptop panel (sway moves its workspaces off it); then (re)evaluate the
#          battery suspend countdown.
#   off -- lid opened: re-enable the panel and cancel any pending suspend.
case "${1:-}" in
  on)
    if @docked@; then
      # Docked: switch everything to the external monitor; don't lock or suspend
      # (logind also ignores the lid when docked).
      swaymsg 'output eDP-1 disable'
    else
      # Not docked: lock now, here in the session rather than relying only on
      # logind's HandleLidSwitch=lock -- logind ignores the lid switch for ~30s
      # after resume (HoldoffTimeoutSec), so closing the lid right after waking
      # wouldn't otherwise lock. loginctl lock-session is idempotent, so the
      # redundant logind lock outside that window is harmless.
      loginctl lock-session
    fi
    @lid-suspend@ arm
    ;;
  off)
    swaymsg 'output eDP-1 enable'
    systemctl --user stop lid-suspend.timer
    ;;
  *)
    echo "usage: lid-switch {on|off}" >&2
    exit 2
    ;;
esac
