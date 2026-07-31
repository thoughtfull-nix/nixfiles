#!@bash@
set -euo pipefail

# Fuzzel-driven menu for the Waybar custom/network-wifi widget's primary
# click, modeled on iwmenu's own menu tree (github.com/e-tho/iwmenu) but
# talking to NetworkManager via nmcli instead of iwd's D-Bus API -- see
# graphical.nix for why Wi-Fi moved off iwd onto NetworkManager. Icons are
# iwmenu's own Nerd Font codepoints (its src/icons.rs font_icons table),
# the same glyph set ethernet-menu.bash already uses for connect/disconnect/
# back/settings, so this looks the same as before.

icon_scan=""
icon_settings="󰒓"
icon_connect="󰌷"
icon_disconnect="󰌸"
icon_forget="󰍷"
icon_autoconnect_on="󰁪"
icon_autoconnect_off="󱧧"
icon_back="󰁍"
icon_connected="⏺"
icon_signal_weak_open="󱛋"
icon_signal_weak_secure="󰤡"
icon_signal_ok_open="󱛌"
icon_signal_ok_secure="󰤤"
icon_signal_good_open="󱛍"
icon_signal_good_secure="󰤧"
icon_signal_excellent_open="󱛎"
icon_signal_excellent_secure="󰤪"

scan_label="${icon_scan} Scan"
settings_label="${icon_settings} Settings"

# nmcli reports SIGNAL as a 0-100 quality percentage rather than dBm, so
# these quartile cuts are an approximation of iwmenu's own RSSI thresholds.
signal_icon() {
  local signal=$1 secure=$2
  if ((signal < 25)); then
    [[ ${secure} == secure ]] && printf '%s' "${icon_signal_weak_secure}" || printf '%s' "${icon_signal_weak_open}"
  elif ((signal < 50)); then
    [[ ${secure} == secure ]] && printf '%s' "${icon_signal_ok_secure}" || printf '%s' "${icon_signal_ok_open}"
  elif ((signal < 75)); then
    [[ ${secure} == secure ]] && printf '%s' "${icon_signal_good_secure}" || printf '%s' "${icon_signal_good_open}"
  else
    [[ ${secure} == secure ]] && printf '%s' "${icon_signal_excellent_secure}" || printf '%s' "${icon_signal_excellent_open}"
  fi
}

mapfile -t devfields < <(@network-device@ wifi)
dev="${devfields[0]:-}"
[[ -z ${dev} ]] && exit 0

# Power the radio on automatically if it's off, with no interactive prompt
# -- simpler than replicating iwmenu's own "Power on device" menu entry, and
# matches what the previous iwd-based wrapper already did here.
radio=$(@nmcli@ -g WIFI general status 2>/dev/null) || radio=""
if [[ ${radio} != "enabled" ]]; then
  @nmcli@ radio wifi on || true
  @systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
  # Poll the device's own STATE, not just its presence: nmcli lists a wifi
  # device regardless of whether the radio is powered (dev above was
  # already resolved before this check), but STATE is "unavailable" until
  # the driver/firmware actually comes up after power-on -- the nmcli
  # analog of the old iwd-based wrapper's Station Scanning poll, which
  # waited on a signal that genuinely changed after power-on rather than
  # one already true beforehand.
  for _ in $(seq 1 20); do
    mapfile -t devfields < <(@network-device@ wifi)
    state="${devfields[1]:-}"
    [[ -n ${state} && ${state} != "unavailable" ]] && break
    sleep 0.25
  done
fi

while true; do
  # Known wifi connection profiles, keyed by SSID rather than nmcli's
  # connection NAME -- NAME can differ from SSID (nmcli appends a suffix
  # like "setecastronomy 1" when a second profile shares an SSID), so
  # known-ness and autoconnect state are looked up per-profile via each
  # profile's actual 802-11-wireless.ssid. Re-queried every pass through
  # this loop (unlike ethernet-menu.bash's one-shot query) because Scan
  # loops back here needing fresh scan results.
  declare -A known_uuid=()
  declare -A known_autoconnect=()
  while IFS=: read -r uuid type; do
    [[ ${type} == "802-11-wireless" ]] || continue
    ssid=$(@nmcli@ --escape no -g 802-11-wireless.ssid connection show "${uuid}" 2>/dev/null) || continue
    [[ -z ${ssid} ]] && continue
    [[ -n ${known_uuid[${ssid}]:-} ]] && continue
    autoconnect=$(@nmcli@ -g connection.autoconnect connection show "${uuid}" 2>/dev/null) || autoconnect="yes"
    known_uuid[${ssid}]="${uuid}"
    known_autoconnect[${ssid}]="${autoconnect}"
  done < <(@nmcli@ -t -f UUID,TYPE connection show 2>/dev/null)

  # Scanned access points, deduped by SSID and skipping hidden networks
  # (blank SSID) -- iwmenu doesn't show those either. --escape no turns off
  # nmcli's colon-escaping of field values entirely rather than having to
  # undo it afterwards (as ethernet-menu.bash does for connection names) --
  # safe here because SSID is the last requested field.
  #
  # A network with several access points sharing one SSID (mesh, repeaters,
  # enterprise APs) gets one row per BSSID from nmcli, signal-sorted -- the
  # BSSID actually in use isn't necessarily the strongest, i.e. isn't
  # necessarily the first row seen for that SSID. Keeping only the
  # first-seen row unconditionally silently drops the in-use marker if some
  # other BSSID for the same SSID happens to be stronger, which is what
  # broke Connect-vs-Disconnect detection on real hardware -- so the first
  # row seen sets the signal/security shown (still the strongest, for the
  # icon), but any later row for the same SSID that's in use still upgrades
  # the connected flag.
  declare -a ap_order=()
  declare -A ap_inuse=()
  declare -A ap_signal=()
  declare -A ap_security=()
  while IFS=: read -r inuse signal security ssid; do
    [[ -z ${ssid} ]] && continue
    if [[ -z ${ap_signal[${ssid}]:-} ]]; then
      ap_order+=("${ssid}")
      ap_inuse[${ssid}]="${inuse}"
      ap_signal[${ssid}]="${signal}"
      ap_security[${ssid}]="${security}"
    elif [[ ${inuse} == "*" ]]; then
      ap_inuse[${ssid}]="*"
    fi
  done < <(@nmcli@ --escape no -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list ifname "${dev}" 2>/dev/null)

  # Known networks are listed before new ones regardless of signal (each
  # group keeps its own signal order), matching iwmenu's own
  # show_main_menu, which renders known_networks then new_networks.
  declare -a known_menu_ssid=()
  declare -a known_menu_lines=()
  declare -a new_menu_ssid=()
  declare -a new_menu_lines=()
  declare -A menu_secure=()
  for ssid in "${ap_order[@]}"; do
    security="${ap_security[${ssid}]}"
    secure="open"
    [[ -n ${security} && ${security} != "--" ]] && secure="secure"
    menu_secure[${ssid}]="${secure}"
    icon=$(signal_icon "${ap_signal[${ssid}]:-0}" "${secure}")
    label="${icon} ${ssid}"
    [[ ${ap_inuse[${ssid}]} == "*" ]] && label="${label} ${icon_connected}"
    if [[ -n ${known_uuid[${ssid}]:-} ]]; then
      known_menu_ssid+=("${ssid}")
      known_menu_lines+=("${label}")
    else
      new_menu_ssid+=("${ssid}")
      new_menu_lines+=("${label}")
    fi
  done

  menu_ssid=("${known_menu_ssid[@]}" "${new_menu_ssid[@]}")
  menu_lines=("${known_menu_lines[@]}" "${new_menu_lines[@]}")
  full_lines=("${scan_label}" "${menu_lines[@]}")
  settings_index=${#full_lines[@]}
  full_lines+=("${settings_label}")

  # See ethernet-menu.bash's note on `|| true`: fuzzel exits non-zero on
  # Escape/right-click, which `errexit` would otherwise treat as a script
  # failure right at the assignment.
  index=$(printf '%s\n' "${full_lines[@]}" | @fuzzel@ --dmenu --minimal-lines --index) || true
  [[ -z ${index} ]] && exit 0

  if ((index == 0)); then
    @nmcli@ device wifi rescan ifname "${dev}" &>/dev/null || true
    sleep 2
    continue
  fi

  if ((index == settings_index)); then
    @nm-connection-editor@ -t 802-11-wireless -s &
    exit 0
  fi

  ssid="${menu_ssid[index - 1]}"
  uuid="${known_uuid[${ssid}]:-}"

  if [[ -n ${uuid} ]]; then
    # Known network: submenu, looked up by fuzzel's numeric --index rather
    # than by matching label text back to a map (ethernet-menu.bash's
    # reasoning for the same choice applies here too).
    is_connected=false
    [[ ${full_lines[index]} == *"${icon_connected}" ]] && is_connected=true
    if ${is_connected}; then
      connect_label="${icon_disconnect} Disconnect"
    else
      connect_label="${icon_connect} Connect"
    fi
    forget_label="${icon_forget} Forget"
    back_label="${icon_back} Back"

    # A nested loop, not a single pass: toggling autoconnect below redisplays
    # this same network's submenu (with the toggled label) instead of
    # bouncing back to the top-level list, matching iwmenu's own
    # handle_network_menu behavior.
    while true; do
      if [[ ${known_autoconnect[${ssid}]} == "yes" ]]; then
        autoconnect_label="${icon_autoconnect_off} Disable autoconnect"
      else
        autoconnect_label="${icon_autoconnect_on} Enable autoconnect"
      fi

      sub_selection=$(
        printf '%s\n' "${connect_label}" "${forget_label}" "${autoconnect_label}" "${back_label}" |
          @fuzzel@ --dmenu --minimal-lines --placeholder "Manage ${ssid}"
      ) || true

      case "${sub_selection}" in
        "${connect_label}")
          if ${is_connected}; then
            @nmcli@ connection down uuid "${uuid}" || true
          else
            # ifname is required here, not optional: without it, nmcli's
            # automatic device selection skips wlan0 if it's already active
            # with a different network (switching networks is exactly the
            # common case for this menu item) and falls through to
            # reporting some other, unrelated device as "not suitable" --
            # rather than just switching wlan0 over, as the GUI would.
            @nmcli@ connection up uuid "${uuid}" ifname "${dev}" || true
          fi
          @systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
          exit 0
          ;;
        "${forget_label}")
          @nmcli@ connection delete uuid "${uuid}" || true
          @systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
          exit 0
          ;;
        "${autoconnect_label}")
          if [[ ${known_autoconnect[${ssid}]} == "yes" ]]; then
            @nmcli@ connection modify uuid "${uuid}" connection.autoconnect no || true
            known_autoconnect[${ssid}]="no"
          else
            @nmcli@ connection modify uuid "${uuid}" connection.autoconnect yes || true
            known_autoconnect[${ssid}]="yes"
          fi
          continue
          ;;
        "${back_label}")
          break
          ;;
        *)
          exit 0
          ;;
      esac
    done
    continue
  fi

  # New network with no saved profile: prompt for a passphrase if secure,
  # then connect straight away -- no submenu, same as iwmenu's own
  # perform_new_network_connection. Empty stdin (</dev/null) mirrors
  # iwmenu's own passphrase prompt, which shows no candidates for fuzzel's
  # dmenu mode to match against -- pressing enter after typing just returns
  # the typed text.
  password_args=()
  if [[ ${menu_secure[${ssid}]:-open} == "secure" ]]; then
    passphrase=$(@fuzzel@ --dmenu --minimal-lines --password --placeholder "${ssid}" </dev/null) || true
    [[ -z ${passphrase} ]] && exit 0
    password_args=(password "${passphrase}")
  fi
  @nmcli@ device wifi connect "${ssid}" ifname "${dev}" "${password_args[@]}" || true
  @systemctl@ --user kill --signal=RTMIN+5 waybar.service || true
  exit 0
done
