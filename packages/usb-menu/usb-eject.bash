#!@bash@
set -euo pipefail

devices_json=$(@lsblk@ -J -o NAME,SIZE,TYPE,MOUNTPOINT,HOTPLUG 2>/dev/null || echo '{"blockdevices":[]}')

devices=$(@jq@ -r '
  .blockdevices[]
  | select(.hotplug == true and .type == "disk")
  | "/dev/\(.name) (\(.size))"
' <<<"$devices_json")

if [[ -z $devices ]]; then
  @notify_send@ -u normal "USB Devices" "No USB devices found"
  exit 0
fi

selected=$(@fuzzel@ --dmenu --width=40 --prompt "Eject: " <<<"$devices")
if [[ -z $selected ]]; then
  exit 0
fi

device=$(echo "$selected" | cut -d' ' -f1)
if output=$(@udisksctl@ power-off -b "$device" 2>&1); then
  @notify_send@ -u normal "USB Devices" "Ejected $device"
else
  @notify_send@ -u critical "USB Devices" "$output"
fi
