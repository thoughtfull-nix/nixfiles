#!@bash@
set -euo pipefail

# Toggles the Wi-Fi radio. Unlike iwd, NetworkManager autoconnects to the
# best-signal known network on its own once the radio is back on -- no need
# to replicate that logic here (the old iwd-based version had to, since iwd
# permanently disables autoconnect on a station after any explicit
# disconnect, and re-enabling the radio alone doesn't undo that).
mapfile -t fields < <(@network-device@ wifi)
dev="${fields[0]:-}"
[[ -z ${dev} ]] && exit 0

radio=$(@nmcli@ -g WIFI general status 2>/dev/null) || radio=""
if [[ ${radio} == "enabled" ]]; then
  @nmcli@ radio wifi off || true
else
  @nmcli@ radio wifi on || true
fi

# custom/network-wifi polls on a 15s interval, so without an explicit nudge
# here the icon would show stale state for up to that long after toggling.
@systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
