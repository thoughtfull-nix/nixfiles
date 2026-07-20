#!@bash@
set -euo pipefail

# Fuzzel-driven menu for the Waybar custom/network-ethernet widget's primary
# click. Lists every Ethernet connection profile (not just the currently
# active one) so any saved profile can be connected, edited, or deleted.
# Selecting a profile opens a submenu; "Back" returns here without exiting.

icon_connection="󰈀"
icon_connect="󰌷"
icon_disconnect="󰌸"
icon_edit=""
icon_delete="󰗨"
icon_back="󰁍"
icon_new=""
icon_settings="󰒓"

new_label="${icon_new} New connection"
settings_label="${icon_settings} Settings"

# Queried once, up front: this script always exits immediately after any
# action that could change connection state (connect/disconnect/delete),
# so nothing can go stale underneath the "Back" path re-showing this same
# list -- and skipping a second nmcli round-trip there avoids a visible
# gap between the submenu closing and the top-level fuzzel reopening.
#
# Looked up by fuzzel's numeric --index rather than by matching the
# displayed label text back to a map: two connection profiles are allowed
# to share the same NAME, which would otherwise collide if the label were
# used as an associative-array key.
declare -a menu_uuid=()
declare -a menu_device=()
declare -a menu_name=()
declare -a menu_lines=()
while IFS=: read -r uuid type device name; do
  [[ ${type} == "802-3-ethernet" ]] || continue
  [[ -z ${name} ]] && continue
  # NAME is queried last so a colon embedded in a profile name -- nmcli
  # backslash-escapes it, but it's still a literal ":" -- can't shift
  # UUID/TYPE/DEVICE out of place: `read` with a fixed variable count
  # folds any of its own remaining colons into the last variable intact.
  # nmcli's terse output backslash-escapes literal colons (e.g. a profile
  # named "foo:bar") and literal backslashes (e.g. "foo\bar" becomes
  # "foo\\bar") so the colon-escape is unambiguous. Undo the backslash
  # escape first via a placeholder so a doubled backslash doesn't get
  # mistaken for an escaped colon partway through.
  name="${name//\\\\/$'\x01'}"
  name="${name//\\:/:}"
  name="${name//$'\x01'/\\}"
  menu_uuid+=("${uuid}")
  menu_device+=("${device}")
  menu_name+=("${name}")
  menu_lines+=("${icon_connection} ${name}")
done < <(@nmcli@ -t -f UUID,TYPE,DEVICE,NAME connection show 2>/dev/null)

new_index=${#menu_lines[@]}
menu_lines+=("${new_label}")
settings_index=${#menu_lines[@]}
menu_lines+=("${settings_label}")

while true; do
  # fuzzel exits non-zero (2 on Escape/right-click, 1 if dmenu mode never
  # got a selection) whenever nothing was chosen, which `errexit` would
  # otherwise treat as a script failure right at the assignment -- `|| true`
  # neutralizes that so the explicit empty check below actually runs.
  index=$(printf '%s\n' "${menu_lines[@]}" | @fuzzel@ --dmenu --minimal-lines --index) || true
  [[ -z ${index} ]] && exit 0

  if ((index == new_index)); then
    @nm-connection-editor@ -t 802-3-ethernet --create &
    exit 0
  elif ((index == settings_index)); then
    @nm-connection-editor@ -t 802-3-ethernet -s &
    exit 0
  fi

  uuid="${menu_uuid[index]}"
  device="${menu_device[index]}"
  name="${menu_name[index]}"

  if [[ -n ${device} ]]; then
    connect_label="${icon_disconnect} Disconnect"
  else
    connect_label="${icon_connect} Connect"
  fi
  edit_label="${icon_edit} Edit"
  delete_label="${icon_delete} Delete"
  back_label="${icon_back} Back"

  # See the `|| true` note above: a cancelled submenu must fall through to
  # the `*)` case below instead of triggering `errexit`.
  sub_selection=$(
    printf '%s\n' "${connect_label}" "${edit_label}" "${delete_label}" "${back_label}" |
      @fuzzel@ --dmenu --minimal-lines --placeholder "Manage ${name}"
  ) || true

  case "${sub_selection}" in
    "${connect_label}")
      if [[ -n ${device} ]]; then
        @nmcli@ connection down uuid "${uuid}"
      else
        @nmcli@ connection up uuid "${uuid}"
      fi
      exit 0
      ;;
    "${edit_label}")
      @nm-connection-editor@ -e "${uuid}" &
      exit 0
      ;;
    "${delete_label}")
      confirm_yes="Yes"
      confirm_no="No"
      confirm=$(
        printf '%s\n' "${confirm_no}" "${confirm_yes}" |
          @fuzzel@ --dmenu --minimal-lines --placeholder "Delete ${name}?"
      ) || true
      [[ ${confirm} == "${confirm_yes}" ]] && @nmcli@ connection delete uuid "${uuid}"
      exit 0
      ;;
    "${back_label}")
      continue
      ;;
    *)
      exit 0
      ;;
  esac
done
