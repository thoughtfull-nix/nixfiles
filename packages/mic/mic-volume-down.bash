#!/usr/bin/env bash
set -euo pipefail
@pactl@ set-source-volume @DEFAULT_SOURCE@ -5%
@canberra-gtk-play@ --id=audio-volume-change || true
@mic-status@
# See kanshi-active.bash for why this signals the unit rather than pkill -x waybar.
@systemctl@ --user kill --signal=RTMIN+7 waybar.service || true
