#!@bash@
set -euo pipefail

# Prints the first device of the given nmcli TYPE ("wifi" or "ethernet") and
# its state, one per line, or nothing if no such device exists (or
# NetworkManager is unreachable). Shared by the wifi/ethernet status and
# toggle scripts so device-discovery logic only lives in one place --
# packages/theme-toggle.nix's theme-get is the precedent for this
# status/toggle shared-helper pattern.
type="$1"
# shellcheck disable=SC2016
@nmcli@ -t -f DEVICE,TYPE,STATE device status 2>/dev/null |
  @awk@ -F: -v t="${type}" '$2==t{print $1; print $3; exit}' || true
