#!/usr/bin/env bash
@pactl@ set-source-volume @DEFAULT_SOURCE@ -5%
@canberra-gtk-play@ --id=audio-volume-change
@mic-status@
