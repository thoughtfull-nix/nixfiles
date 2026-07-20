#!@bash@
set -euo pipefail
@pactl@ set-sink-mute @DEFAULT_SINK@ toggle
# See kanshi-active.bash for why this signals the unit rather than pkill -x waybar.
@systemctl@ --user kill --signal=RTMIN+6 waybar.service || true
