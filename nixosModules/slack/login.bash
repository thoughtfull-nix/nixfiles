#!@bash@
set -euo pipefail

# Launch slack through sway's own `exec` -- the way a manual launch from the
# launcher does -- rather than spawning it directly from this systemd service.
# Spawned from the service at boot, slack comes up unable to open links until
# it's quit and relaunched from within the session; execing it through sway
# gives it the same live session context a working manual launch has.
#
# Placement keys on app_id, not pid: `swaymsg exec` doesn't hand back the child
# pid, and slack's single-instance lock can make a launch hand off to a running
# instance and exit without mapping a window (see slack-login.service in
# ../slack.nix), so a pid would name a dead end.
@swaymsg@ 'for_window [app_id="slack"] move to workspace 4'
@swaymsg@ exec @slack@
