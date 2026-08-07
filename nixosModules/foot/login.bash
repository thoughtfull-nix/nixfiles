#!@bash@
set -euo pipefail

# Registering the for_window rule against this exact pid (not swaymsg's own,
# which never owns a window) is what places the new window without
# permanently pinning foot to this workspace -- see foot-login.service in
# ../foot.nix for how this only ever runs once, at login.
@foot@ &
@swaymsg@ "for_window [pid=$!] move to workspace 1"
