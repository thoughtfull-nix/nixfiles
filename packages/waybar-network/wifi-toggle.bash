#!@bash@
set -euo pipefail

# Toggles the Wi-Fi device found by wifi-device: powers the radio off if
# it's currently on, otherwise powers it on and connects to the
# best-signal known network in range -- the iwd equivalent of nmcli's
# best-available-connection reconnect. iwd doesn't autoconnect just
# because the radio is powered on: any explicit Disconnect (from here,
# from wifi-menu.bash's iwmenu, wherever) permanently flips iwd's own
# per-station autoconnect flag off -- see station_dbus_disconnect() in
# iwd's src/station.c ("Disconnect was triggered by the user, don't
# autoconnect"). Nothing resets that flag except an explicit Connect()
# (which is what we do below) or the Station object being destroyed and
# recreated, which only happens by powering the radio fully off and back
# on -- station_create() defaults autoconnect back to true. So this has
# to pick and connect explicitly rather than relying on iwd's own
# autoconnect state machine, and disconnecting once means the *only* way
# back to autoconnecting is either an explicit reconnect (left-click ->
# iwmenu) or a full disable/enable cycle through this script.
#
# custom/network-wifi polls on a 15s interval, so without an explicit
# nudge here the icon would show stale state for up to that long after
# every action. Refresh it (signal 5) after each state change.
mapfile -t fields < <(@wifi-device@)
dev="${fields[0]:-}"
powered="${fields[4]:-}"
[[ -z ${dev} ]] && exit 0

if [[ ${powered} == "true" ]]; then
  @busctl@ --system set-property net.connman.iwd "${dev}" net.connman.iwd.Device Powered b false
  @pkill@ -RTMIN+5 -x waybar || true
  exit 0
fi

@busctl@ --system set-property net.connman.iwd "${dev}" net.connman.iwd.Device Powered b true
@pkill@ -RTMIN+5 -x waybar || true
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

if [[ -n ${best} ]]; then
  @busctl@ --system call net.connman.iwd "${best}" net.connman.iwd.Network Connect
  @pkill@ -RTMIN+5 -x waybar || true
fi
