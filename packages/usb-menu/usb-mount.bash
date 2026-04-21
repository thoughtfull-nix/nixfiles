#!@bash@
set -euo pipefail

devices_json=$(@lsblk@ -J -o NAME,SIZE,TYPE,MOUNTPOINT,HOTPLUG 2>/dev/null || echo '{"blockdevices":[]}')

devices=$(@jq@ -r '
  .blockdevices[]
  | select(.hotplug == true and .type == "disk")
  | (.children // [])[]
  | select(.type == "part" and .mountpoint == null)
  | "/dev/\(.name) (\(.size))"
' <<<"$devices_json")

if [[ -z $devices ]]; then
  @notify_send@ -u normal "USB Devices" "No unmounted USB drives found"
  exit 0
fi

selected=$(@fuzzel@ --dmenu --width=40 --prompt "Mount: " <<<"$devices")
if [[ -z $selected ]]; then
  exit 0
fi

device=$(echo "$selected" | cut -d' ' -f1)
if output=$(@udisksctl@ mount -b "$device" 2>&1); then
  @notify_send@ -u normal "USB Devices" "$output"
else
  @notify_send@ -u critical "USB Devices" "$output"
fi
