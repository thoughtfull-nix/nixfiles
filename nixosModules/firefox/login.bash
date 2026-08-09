#!@bash@
set -euo pipefail

# See ../foot/login.bash for why pid=$! (not swaymsg's own) is what places
# the window without pinning firefox to this workspace afterward. If an
# instance is already running, firefox hands off to it and exits almost
# immediately without mapping its own window -- $! then names a dead end and
# this silently misses, which is a known gap (see firefox-login.service in
# ../firefox.nix), not something this script can detect or fix.
@firefox@ &
@swaymsg@ "for_window [pid=$!] move to workspace 3"
