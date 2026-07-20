#!@bash@
set -euo pipefail

# Powers on the Wi-Fi radio (if it's off) before launching iwmenu, so its
# network-selection menu shows up directly instead of iwmenu's own "Power
# on device" prompt. That prompt doesn't actually gate anything useful:
# iwmenu only picks up iwd's Station D-Bus interface (and so only shows a
# network list) if the radio was already powered when iwmenu started --
# see wifi-device.bash for why Station only exists while powered. Selecting
# "Power on device" works by reinitializing everything from scratch, but
# escaping just quits with the radio silently left on and no menu shown.
# Powering on ourselves first sidesteps that prompt entirely.
#
# custom/network-wifi polls on a 15s interval and iwmenu's own menu
# actions (connect, disconnect, forget) don't know to poke it, so nudge it
# (signal 5) both right after we power on and once iwmenu exits -- whatever
# changed inside its menu shows up immediately instead of waiting out the
# interval.
mapfile -t fields < <(@wifi-device@)
dev="${fields[0]:-}"
powered="${fields[4]:-}"

if [[ -n ${dev} && ${powered} != "true" ]]; then
  # A failed power-on shouldn't abort the script under set -e and leave
  # iwmenu never even attempted -- fall through and let iwmenu try anyway,
  # same as if we hadn't powered on at all.
  @busctl@ --system set-property net.connman.iwd "${dev}" net.connman.iwd.Device Powered b true || true
  @systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
  # Real hardware can take a few seconds to bring the interface up (driver
  # firmware load, etc.) before iwd registers the Station interface --
  # launching iwmenu before that happens makes it silently quit with no
  # menu shown at all (see comment above), so wait longer than it should
  # ever actually take rather than risk cutting this off early. If it still
  # never comes up, say so on stderr rather than launching iwmenu into the
  # same silent failure this script exists to avoid.
  station_ready=false
  for _ in $(seq 1 20); do
    if @busctl@ --system get-property net.connman.iwd "${dev}" net.connman.iwd.Station Scanning &>/dev/null; then
      station_ready=true
      break
    fi
    sleep 0.25
  done
  [[ ${station_ready} == false ]] &&
    echo "wifi-menu: iwd's Station interface never came up after powering on; launching iwmenu anyway" >&2
fi

iwmenu --launcher fuzzel || true
@systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
