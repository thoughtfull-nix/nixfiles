#!@bash@
set -euo pipefail

# Record the kanshi profile that just became active so the Waybar displays
# widget can pick the right icon, then poke Waybar to refresh it. kanshi runs
# this from each profile's `exec` directive, e.g. `exec kanshi-active docked`.
dir="${XDG_RUNTIME_DIR:-/run/user/$UID}/kanshi"
mkdir -p "$dir"
printf '%s\n' "${1:-}" >"$dir/active-profile"

# Refresh custom/displays (signal 4). Ignore failure so switching profiles still
# works when Waybar isn't running.
@pkill@ -RTMIN+4 waybar || true
