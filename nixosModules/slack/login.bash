#!@bash@
set -euo pipefail

# See ../foot/login.bash for why pid=$! (not swaymsg's own) is what places
# the window without pinning slack to this workspace afterward. If an
# instance is already running, slack (Electron's single-instance lock) hands
# off to it and exits almost immediately without mapping its own window --
# $! then names a dead end and this silently misses, which is a known gap
# (see slack-login.service in ../slack.nix), not something this script can
# detect or fix.
@slack@ &
@swaymsg@ "for_window [pid=$!] move to workspace 4"
