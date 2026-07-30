#!@bash@
set -euo pipefail

# Reports Wi-Fi connection state for the Waybar custom/network-wifi widget.
# Device discovery is shared with the Ethernet widget via network-device --
# Wi-Fi is now managed by NetworkManager like any other device (see
# graphical.nix), so this queries nmcli instead of iwd's D-Bus API directly.
mapfile -t fields < <(@network-device@ wifi)
dev="${fields[0]:-}"
state="${fields[1]:-}"

if [[ -z ${dev} ]]; then
  printf '{"text": "󰤭", "tooltip": "No Wi-Fi device", "class": "disabled"}\n'
  exit 0
fi

radio=$(@nmcli@ -g WIFI general status 2>/dev/null) || radio=""
if [[ ${radio} != "enabled" ]]; then
  printf '{"text": "󰤭", "tooltip": "Wi-Fi disabled\\nClick to browse networks\\nRight-click to enable", "class": "disabled"}\n'
  exit 0
fi

if [[ ${state} == connected* ]]; then
  # --escape no turns off nmcli's colon-escaping of field values entirely,
  # rather than having to undo it afterwards (as ethernet-menu.bash does for
  # connection names) -- safe here because SSID is the last requested
  # field, so any raw colon it contains can't be mistaken for a field
  # separator between it and a later column.
  line=$(@nmcli@ --escape no -t -f IN-USE,SIGNAL,SSID device wifi list ifname "${dev}" 2>/dev/null | grep '^\*:') || line=""
  signal="${line#\*:}"
  signal="${signal%%:*}"
  ssid="${line#*:}"
  ssid="${ssid#*:}"

  # nmcli reports SIGNAL as a 0-100 quality percentage, not dBm, so these
  # quartile cuts are an approximation of the -70/-60/-50 dBm 4-bar
  # convention the old iwd-based version used.
  icon="󰤨"
  if [[ ${signal} =~ ^[0-9]+$ ]]; then
    if ((signal < 25)); then
      icon="󰤟"
    elif ((signal < 50)); then
      icon="󰤢"
    elif ((signal < 75)); then
      icon="󰤥"
    fi
  fi
  # shellcheck disable=SC2016
  @jq@ -cn --arg icon "${icon}" --arg ssid "${ssid}" --arg signal "${signal}" \
    '{text: $icon, tooltip: ("Wi-Fi: " + $ssid + " (" + $signal + "% signal)\nClick to browse networks\nRight-click to disable"), class: "connected"}'
else
  printf '{"text": "󰤯", "tooltip": "Wi-Fi disconnected\\nClick to browse networks\\nRight-click to disable", "class": "disconnected"}\n'
fi
