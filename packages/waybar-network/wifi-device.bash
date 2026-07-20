#!@bash@
set -euo pipefail

# Prints the iwd station device's object path, station state, connected
# SSID, (while connected) RSSI in dBm, and whether the radio is powered --
# one per line -- or nothing if no wifi device exists (or iwd is
# unreachable). Wifi is owned directly by iwd rather than NetworkManager
# (see graphical.nix), so this queries iwd's D-Bus objects instead of
# nmcli, which network-device.bash uses for the NetworkManager-managed
# ethernet device. Shared by wifi-status.bash and wifi-toggle.bash so this
# discovery logic only lives in one place -- same reasoning as
# network-device.bash.
#
# The Device interface (and its Mode/Powered properties) persists even
# when the radio is powered off, but iwd drops the Station interface
# entirely in that case -- so State/ConnectedNetwork naturally fall back
# to "disconnected"/"" below, and Powered is the only reliable signal for
# distinguishing "off" from "on but disconnected".
objects=$(@busctl@ --system -j call net.connman.iwd / org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null) || exit 0

# Fields are joined with the unit separator (\x1f), not a tab: bash's read
# treats tab as "IFS whitespace" and collapses consecutive delimiters, so
# an empty field (ssid, whenever disconnected) would silently swallow a
# tab and shift every field after it left -- \x1f isn't whitespace, so
# empty fields are preserved correctly.
# shellcheck disable=SC2016
parsed=$(@jq@ -r '
  .data[0] as $objs
  | ($objs | to_entries[] | select(.value["net.connman.iwd.Device"].Mode.data? == "station")) as $d
  | ($d.value["net.connman.iwd.Station"].ConnectedNetwork.data // "") as $net
  | [
      $d.key,
      ($d.value["net.connman.iwd.Station"].State.data // "disconnected"),
      (if $net != "" then $objs[$net]["net.connman.iwd.Network"].Name.data else "" end),
      (if $d.value["net.connman.iwd.Device"].Powered.data == true then "true" else "false" end)
    ] | join("")
' <<<"${objects}" 2>/dev/null) || exit 0
[[ -z ${parsed} ]] && exit 0

IFS=$'\x1f' read -r dev state ssid powered <<<"${parsed}"

rssi=""
if [[ ${state} == "connected" ]]; then
  rssi=$(
    @busctl@ --system -j call net.connman.iwd "${dev}" net.connman.iwd.StationDiagnostic GetDiagnostics 2>/dev/null |
      @jq@ -r '.data[0].RSSI.data // empty' 2>/dev/null
  ) || rssi=""
fi

printf '%s\n' "${dev}" "${state}" "${ssid}" "${rssi}" "${powered}"
