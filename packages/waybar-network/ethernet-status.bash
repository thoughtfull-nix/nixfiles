#!@bash@
set -euo pipefail

# Reports Ethernet connection state for the Waybar custom/network-ethernet
# widget. Device discovery is shared with ethernet-toggle.bash via
# network-device (see that script for why).
mapfile -t fields < <(@network-device@ ethernet)
dev="${fields[0]:-}"
state="${fields[1]:-}"

if [[ -z ${dev} ]]; then
  printf '{"text": "󰈀", "tooltip": "No Ethernet device", "class": "disabled"}\n'
  exit 0
fi

# NetworkManager reports states like "connected" but also suffixed variants
# such as "connected (externally)" for devices it didn't activate itself, so
# match on the prefix rather than exact equality.
if [[ ${state} == connected* ]]; then
  printf '{"text": "󰈀", "tooltip": "Ethernet connected\\nClick to manage\\nMiddle/right-click to disconnect", "class": "connected"}\n'
else
  printf '{"text": "󰈀", "tooltip": "Ethernet disconnected\\nClick to manage\\nMiddle/right-click to reconnect", "class": "disconnected"}\n'
fi
