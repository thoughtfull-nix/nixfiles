#!@bash@
set -euo pipefail

# Toggles the Wi-Fi device found by network-device: disconnects it if
# connected, otherwise turns the radio on and asks NetworkManager to
# (re)connect using its normal best-available-connection logic.
mapfile -t fields < <(@network-device@ wifi)
dev="${fields[0]:-}"
state="${fields[1]:-}"
[[ -z ${dev} ]] && exit 0

if [[ ${state} == connected* ]]; then
  @nmcli@ device disconnect "${dev}"
else
  @nmcli@ radio wifi on
  @nmcli@ device connect "${dev}"
fi
