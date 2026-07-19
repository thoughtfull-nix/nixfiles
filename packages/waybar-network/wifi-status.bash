#!@bash@
set -euo pipefail

# Reports Wi-Fi connection state for the Waybar custom/network-wifi widget.
# Device discovery is shared with wifi-toggle.bash via wifi-device (see
# that script for why wifi uses iwd directly instead of NetworkManager).
mapfile -t fields < <(@wifi-device@)
dev="${fields[0]:-}"
state="${fields[2]:-}"
ssid="${fields[3]:-}"
rssi="${fields[4]:-}"

if [[ -z ${dev} ]]; then
  printf '{"text": "󰤯", "tooltip": "No Wi-Fi device", "class": "disabled"}\n'
  exit 0
fi

if [[ ${state} == "connected" ]]; then
  # RSSI thresholds follow the common 4-bar convention (excellent >= -50
  # dBm, good >= -60, fair >= -70, weak below that).
  icon="󰤨"
  if [[ ${rssi} =~ ^-?[0-9]+$ ]]; then
    if ((rssi < -70)); then
      icon="󰤟"
    elif ((rssi < -60)); then
      icon="󰤢"
    elif ((rssi < -50)); then
      icon="󰤥"
    fi
  fi
  # shellcheck disable=SC2016
  @jq@ -cn --arg icon "${icon}" --arg ssid "${ssid}" --arg rssi "${rssi}" \
    '{text: $icon, tooltip: ("Wi-Fi: " + $ssid + " (" + $rssi + " dBm)\nClick to browse networks\nRight-click to disconnect"), class: "connected"}'
else
  printf '{"text": "󰤯", "tooltip": "Wi-Fi disconnected\\nClick to browse networks\\nRight-click to reconnect", "class": "disconnected"}\n'
fi
