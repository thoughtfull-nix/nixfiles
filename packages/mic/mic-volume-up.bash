#!/usr/bin/env bash
set -euo pipefail
@pactl@ set-source-volume @DEFAULT_SOURCE@ +5%
@canberra-gtk-play@ --id=audio-volume-change || true
@mic-status@
