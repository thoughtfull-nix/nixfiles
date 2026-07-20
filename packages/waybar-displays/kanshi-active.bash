#!@bash@
set -euo pipefail

# Record the kanshi profile that just became active so the Waybar displays
# widget can pick the right icon, then poke Waybar to refresh it. kanshi runs
# this from each profile's `exec` directive, e.g. `exec kanshi-active docked`.
dir="${XDG_RUNTIME_DIR:-/run/user/$UID}/kanshi"
mkdir -p "$dir"
printf '%s\n' "${1:-}" >"$dir/active-profile"

# Refresh custom/displays (signal 4) by signaling the systemd unit directly
# rather than matching the process by name: Nix wraps the waybar binary (for
# GTK/GIO env vars), so the actual running process is named ".waybar-wrapped"
# on disk -- `pkill -x waybar` (or even an unanchored `pkill waybar`) is
# fragile against that, while systemd already knows the unit's real PID(s)
# regardless of what the wrapped binary calls itself. Ignore failure so
# switching profiles still works when Waybar isn't running.
@systemctl@ --user kill --signal=RTMIN+4 waybar.service || true
