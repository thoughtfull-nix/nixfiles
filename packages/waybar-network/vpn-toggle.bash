#!@bash@
set -euo pipefail

# Starts/stops the wg-quick home VPN. Authorized for non-root callers by the
# polkit rule in nixosModules/vpn.nix, scoped to exactly this unit.
[[ $(@systemctl@ show --property=LoadState --value vpn.service 2>/dev/null || true) == loaded ]] || exit 0

if @systemctl@ is-active --quiet vpn.service; then
  @systemctl@ stop vpn.service
else
  @systemctl@ start vpn.service
fi
