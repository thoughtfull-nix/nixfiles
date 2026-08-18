#!@bash@
set -euo pipefail

# The battery lid-suspend countdown. The condition -- lid closed AND on battery
# AND not docked -- is evaluated at call time, so plugging in AC, docking, or
# reopening the lid all cancel a pending suspend (re-checked at fire time, not
# just when armed).
#
#   arm   (re)start or cancel the countdown to match the current state. Called
#         from the lid bindswitch (lid-switch.bash) and the AC power watcher
#         (lid-power-watch.bash).
#   fire  the countdown's action (lid-suspend.timer -> lid-suspend.service):
#         re-check the condition, then suspend.
#
# LID_STATE_GLOB is overridable for tests.

lid_closed() {
  local file state
  for file in ${LID_STATE_GLOB:-/proc/acpi/button/lid/*/state}; do
    read -r _ state <"$file" 2>/dev/null || continue
    [[ $state == closed ]] && return 0
  done
  return 1
}

should_suspend() {
  lid_closed && ! @on-ac@ && ! @docked@
}

case "${1:-}" in
  arm)
    if should_suspend; then
      systemctl --user start lid-suspend.timer
    else
      systemctl --user stop lid-suspend.timer
    fi
    ;;
  fire)
    if should_suspend; then
      systemctl suspend
    fi
    ;;
  *)
    echo "usage: lid-suspend {arm|fire}" >&2
    exit 2
    ;;
esac
