#!@bash@
set -euo pipefail

# Reports Wi-Fi connection state for the Waybar custom/network-wifi widget.
# Device discovery is shared with wifi-toggle.bash via network-device (see
# that script for why).
mapfile -t fields < <(@network-device@ wifi)
dev="${fields[0]:-}"
state="${fields[1]:-}"

if [[ -z ${dev} ]]; then
  printf '{"text": "󰤯", "tooltip": "No Wi-Fi device", "class": "disabled"}\n'
  exit 0
fi

# NetworkManager reports states like "connected" but also suffixed variants
# such as "connected (externally)" for devices it didn't activate itself, so
# match on the prefix rather than exact equality.
if [[ ${state} == connected* ]]; then
  # nmcli's terse output backslash-escapes literal colons within a field
  # (e.g. an SSID containing ":"). Isolate the trailing numeric signal first
  # (it can't contain a colon), then unescape the remaining SSID.
  # shellcheck disable=SC2016
  raw=$(@nmcli@ -t -f active,ssid,signal dev wifi 2>/dev/null | @awk@ -F: '$1=="yes"{print; exit}') || true
  rest="${raw#yes:}"
  signal="${rest##*:}"
  ssid="${rest%:*}"
  ssid="${ssid//\\:/:}"
  icon="󰤨"
  if [[ ${signal:-0} =~ ^[0-9]+$ ]]; then
    if ((signal <= 25)); then
      icon="󰤟"
    elif ((signal <= 50)); then
      icon="󰤢"
    elif ((signal <= 75)); then
      icon="󰤥"
    fi
  fi
  # shellcheck disable=SC2016
  @jq@ -cn --arg icon "${icon}" --arg ssid "${ssid}" --arg signal "${signal}" \
    '{text: $icon, tooltip: ("Wi-Fi: " + $ssid + " (" + $signal + "%)\nClick to disconnect"), class: "connected"}'
else
  printf '{"text": "󰤯", "tooltip": "Wi-Fi disconnected\\nClick to reconnect, right-click to browse", "class": "disconnected"}\n'
fi
