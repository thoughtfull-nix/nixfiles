#!@bash@
@pactl@ set-sink-volume @DEFAULT_SINK@ -5%
@canberra-gtk-play@ --id=audio-volume-change
@speaker-status@
