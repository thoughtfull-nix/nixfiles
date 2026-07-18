#!@bash@
set -euo pipefail

# Toggles the Ethernet device found by network-device.
mapfile -t fields < <(@network-device@ ethernet)
dev="${fields[0]:-}"
state="${fields[1]:-}"
[[ -z ${dev} ]] && exit 0

if [[ ${state} == connected* ]]; then
  @nmcli@ device disconnect "${dev}"
else
  @nmcli@ device connect "${dev}"
fi
