#!@bash@
set -euo pipefail

# Toggle between the docked and undocked kanshi profiles. Bound to the Waybar
# displays widget's right-click. The active profile is recorded by kanshi-active
# when kanshi applies a profile.
file="${XDG_RUNTIME_DIR:-/run/user/$UID}/kanshi/active-profile"
current="$(cat "$file" 2>/dev/null || true)"

case "$current" in
  docked) target=undocked ;;
  *) target=docked ;;
esac

@kanshictl@ switch "$target"
