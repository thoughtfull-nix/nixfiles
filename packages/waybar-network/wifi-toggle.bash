#!@bash@
set -euo pipefail

# Toggles the Wi-Fi device found by wifi-device: disconnects it if
# connected, otherwise connects to the best-signal known network in range --
# the iwd equivalent of nmcli's best-available-connection reconnect. iwd
# doesn't autoconnect just because the radio is powered on (an explicit
# Disconnect suppresses it), so this has to pick and connect explicitly
# rather than relying on iwd's own autoconnect state machine.
mapfile -t fields < <(@wifi-device@)
dev="${fields[0]:-}"
state="${fields[1]:-}"
[[ -z ${dev} ]] && exit 0

if [[ ${state} == "connected" ]]; then
  @busctl@ --system call net.connman.iwd "${dev}" net.connman.iwd.Station Disconnect
  exit 0
fi

@busctl@ --system set-property net.connman.iwd "${dev}" net.connman.iwd.Device Powered b true
@busctl@ --system call net.connman.iwd "${dev}" net.connman.iwd.Station Scan 2>/dev/null || true
for _ in 1 2 3 4 5; do
  scanning=$(@busctl@ --system get-property net.connman.iwd "${dev}" net.connman.iwd.Station Scanning 2>/dev/null) || break
  [[ ${scanning} != *true* ]] && break
  sleep 1
done

ordered=$(@busctl@ --system -j call net.connman.iwd "${dev}" net.connman.iwd.Station GetOrderedNetworks 2>/dev/null) || exit 0
objects=$(@busctl@ --system -j call net.connman.iwd / org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null) || exit 0

best=$(
  # shellcheck disable=SC2016
  @jq@ -n -r --argjson objects "${objects}" --argjson ordered "${ordered}" '
    $objects.data[0] as $o
    | $ordered.data[0][]
    | .[0] as $path
    | select($o[$path]["net.connman.iwd.Network"].KnownNetwork.data? != null)
    | $path
  ' 2>/dev/null | head -n1
) || exit 0

[[ -n ${best} ]] && @busctl@ --system call net.connman.iwd "${best}" net.connman.iwd.Network Connect
