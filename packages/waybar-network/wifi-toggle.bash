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

# A failed set-property shouldn't abort the script under set -e before the
# refresh below runs -- if it really failed, the icon just reflects that
# nothing changed, which is accurate.
if [[ ${powered} == "true" ]]; then
  @busctl@ --system set-property net.connman.iwd "${dev}" net.connman.iwd.Device Powered b false || true
  @systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
  exit 0
fi

@busctl@ --system set-property net.connman.iwd "${dev}" net.connman.iwd.Device Powered b true || true
@systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  @busctl@ --system get-property net.connman.iwd "${dev}" net.connman.iwd.Station Scanning &>/dev/null && break
  sleep 0.25
done
@busctl@ --system call net.connman.iwd "${dev}" net.connman.iwd.Station Scan 2>/dev/null || true
for _ in 1 2 3 4 5; do
  scanning=$(@busctl@ --system get-property net.connman.iwd "${dev}" net.connman.iwd.Station Scanning 2>/dev/null) || break
  [[ ${scanning} != *true* ]] && break
  sleep 1
done

# GetOrderedNetworks returns every visible network (known or not), sorted
# best-signal-first. KnownNetwork is only present on a Network object at
# all if it's actually a known one, so a per-candidate property read (not
# a full ObjectManager tree dump) is enough to find the first one we can
# connect to.
ordered=$(@busctl@ --system -j call net.connman.iwd "${dev}" net.connman.iwd.Station GetOrderedNetworks 2>/dev/null) || exit 0

best=""
while IFS= read -r path; do
  if @busctl@ --system get-property net.connman.iwd "${path}" net.connman.iwd.Network KnownNetwork &>/dev/null; then
    best="${path}"
    break
  fi
done < <(@jq@ -r '.data[0][][0] // empty' <<<"${ordered}" 2>/dev/null)

if [[ -n ${best} ]]; then
  @busctl@ --system call net.connman.iwd "${best}" net.connman.iwd.Network Connect
  @systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
fi
