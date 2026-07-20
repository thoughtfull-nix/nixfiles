#!/usr/bin/env bash
@pactl@ set-source-mute @DEFAULT_SOURCE@ toggle
@mic-status@
# See kanshi-active.bash for why this signals the unit rather than pkill -x waybar.
@systemctl@ --user kill --signal=RTMIN+7 waybar.service || true
