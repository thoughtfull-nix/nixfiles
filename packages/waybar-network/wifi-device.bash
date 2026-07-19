#!@bash@
set -euo pipefail

# Prints the iwd station device's object path, powered state ("on"/"off"),
# station state, connected SSID, and (while connected) RSSI in dBm -- one
# per line -- or nothing if no wifi device exists (or iwd is unreachable).
# Wifi is owned directly by iwd rather than NetworkManager (see
# graphical.nix), so this queries iwd's D-Bus objects instead of nmcli,
# which network-device.bash uses for the NetworkManager-managed ethernet
# device. Shared by wifi-status.bash and wifi-toggle.bash so this discovery
# logic only lives in one place -- same reasoning as network-device.bash.
objects=$(@busctl@ --system -j call net.connman.iwd / org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null) || exit 0

# shellcheck disable=SC2016
parsed=$(@jq@ -r '
  .data[0] as $objs
  | ($objs | to_entries[] | select(.value["net.connman.iwd.Device"].Mode.data? == "station")) as $d
  | ($d.value["net.connman.iwd.Station"].ConnectedNetwork.data // "") as $net
  | [
      $d.key,
      ($d.value["net.connman.iwd.Device"].Powered.data | if . then "on" else "off" end),
      ($d.value["net.connman.iwd.Station"].State.data // "disconnected"),
      (if $net != "" then $objs[$net]["net.connman.iwd.Network"].Name.data else "" end)
    ] | @tsv
' <<<"${objects}" 2>/dev/null) || exit 0
[[ -z ${parsed} ]] && exit 0

IFS=$'\t' read -r dev powered state ssid <<<"${parsed}"

rssi=""
if [[ ${state} == "connected" ]]; then
  rssi=$(
    @busctl@ --system -j call net.connman.iwd "${dev}" net.connman.iwd.StationDiagnostic GetDiagnostics 2>/dev/null |
      @jq@ -r '.data[0].RSSI.data // empty' 2>/dev/null
  ) || rssi=""
fi

printf '%s\n' "${dev}" "${powered}" "${state}" "${ssid}" "${rssi}"
