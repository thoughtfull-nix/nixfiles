#!@bash@
set -euo pipefail

# Get list of yubikey serial numbers
serials=$(@ykman@ list --serials)

if [[ -z $serials ]]; then
  @notify_send@ -u critical "No YubiKey detected"
  exit 1
fi

# Count number of yubikeys
serial_count=$(echo "$serials" | wc -l)

if [[ $serial_count -eq 1 ]]; then
  serial="$serials"
else
  # Multiple yubikeys, use fuzzel to select
  serial=$(echo "$serials" | @fuzzel@ --dmenu --width=40 --prompt "Select YubiKey: ")
  if [[ -z $serial ]]; then
    exit 0
  fi
fi

# Get list of TOTP accounts from the selected yubikey
accounts=$(@ykman@ --device "$serial" oath accounts list 2>/dev/null)

if [[ -z $accounts ]]; then
  @notify_send@ -u critical "No OATH accounts on YubiKey $serial"
  exit 1
fi

# Create arrays for display and original account names
declare -a display_accounts
declare -a original_accounts

while IFS= read -r account; do
  original_accounts+=("$account")
  # Replace first : with → for nicer display
  display_accounts+=("${account/:/ → }")
done <<<"$accounts"

# Use fuzzel to select an account
selected_display=$(printf '%s\n' "${display_accounts[@]}" | @fuzzel@ --dmenu --width=60 --prompt "Select account: ")

if [[ -z $selected_display ]]; then
  exit 0
fi

# Map the display selection back to the original account name
for i in "${!display_accounts[@]}"; do
  if [[ ${display_accounts[$i]} == "$selected_display" ]]; then
    account="${original_accounts[$i]}"
    break
  fi
done

# Get the TOTP code and copy to clipboard
code=$(@ykman@ --device "$serial" oath accounts code -s "$account")
echo -n "$code" | @wl_copy@

@notify_send@ -c no-sound "TOTP code copied" "$selected_display"
