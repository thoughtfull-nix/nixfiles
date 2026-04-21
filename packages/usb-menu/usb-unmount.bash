#!@bash@
set -euo pipefail

devices_json=$(@lsblk@ -J -o NAME,SIZE,TYPE,MOUNTPOINT,HOTPLUG 2>/dev/null || echo '{"blockdevices":[]}')

devices=$(@jq@ -r '
  .blockdevices[]
  | select(.hotplug == true and .type == "disk")
  | (.children // [])[]
  | select(.type == "part" and .mountpoint != null)
  | "/dev/\(.name) (\(.mountpoint))"
' <<<"$devices_json")

if [[ -z $devices ]]; then
  @notify_send@ -u normal "USB Devices" "No mounted USB drives found"
  exit 0
fi

selected=$(@fuzzel@ --dmenu --width=50 --prompt "Unmount: " <<<"$devices")
if [[ -z $selected ]]; then
  exit 0
fi

device=$(echo "$selected" | cut -d' ' -f1)
mountpoint=${selected#*\(}
mountpoint=${mountpoint%)}
if output=$(@udisksctl@ unmount -b "$device" 2>&1); then
  @notify_send@ -u normal "USB Devices" "Unmounted $device from $mountpoint"
else
  @notify_send@ -u critical "USB Devices" "$output"
fi
