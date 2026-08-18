#!@bash@
set -euo pipefail

# Exit 0 when docked -- i.e. some non-eDP DRM connector is connected (an external
# monitor or dock) -- matching logind's own HandleLidSwitchDocked notion, so the
# lid handling here and logind's agree on what "docked" means. DRM_ROOT is
# overridable for tests.
root="${DRM_ROOT:-/sys/class/drm}"

shopt -s nullglob
for status in "$root"/*/status; do
  # The internal panel (eDP) doesn't count -- only external outputs make us docked.
  case $status in
    *eDP*) continue ;;
  esac
  read -r state <"$status" 2>/dev/null || continue
  [[ $state == connected ]] && exit 0
done
exit 1
