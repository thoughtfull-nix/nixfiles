#!@bash@
set -euo pipefail
@pactl@ set-sink-volume @DEFAULT_SINK@ -5%
@canberra-gtk-play@ --id=audio-volume-change || true
@speaker-status@
