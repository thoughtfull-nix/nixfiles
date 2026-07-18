#!@bash@
set -euo pipefail

# Reports connection state of the wg-quick home VPN (nixosModules/vpn.nix
# aliases wg-quick-wg0.service to vpn.service). Querying is-active needs no
# elevated privilege; only starting/stopping it does (see vpn-toggle.bash).
load_state="$(@systemctl@ show --property=LoadState --value vpn.service 2>/dev/null || true)"
if [[ ${load_state} != loaded ]]; then
  printf '{"text": "󰦝", "tooltip": "VPN unavailable", "class": "disabled"}\n'
  exit 0
fi

if @systemctl@ is-active --quiet vpn.service; then
  printf '{"text": "󰦝", "tooltip": "VPN connected\\nClick to disconnect", "class": "connected"}\n'
else
  printf '{"text": "󰦝", "tooltip": "VPN disconnected\\nClick to connect", "class": "disconnected"}\n'
fi
