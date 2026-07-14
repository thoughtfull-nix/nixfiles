#!@bash@
set -euo pipefail

# Print the Waybar icon for the active kanshi profile: a laptop when undocked, a
# monitor when docked (or when the profile is unknown, e.g. before kanshi has
# applied one). kanshi-active records the profile name and signals Waybar
# (SIGRTMIN+4, see custom/displays "signal") to re-run this script.
file="${XDG_RUNTIME_DIR:-/run/user/$UID}/kanshi/active-profile"
profile="$(cat "$file" 2>/dev/null || true)"

case "$profile" in
  undocked) printf '%s\n' '󰌢' ;;
  *) printf '%s\n' '󰍹' ;;
esac
