#!@bash@
set -euo pipefail

# rage passes along the plugin's generic PIN prompt with a 30 second timeout; say what the PIN
# unlocks, and wait for it.
sed -u \
  -e 's/^SETDESC Please enter you PIN:$/SETDESC Enter your FIDO2 PIN to unlock GNOME Keyring/' \
  -e 's/^SETPROMPT .*/SETPROMPT PIN/' \
  -e 's/^SETTIMEOUT .*/SETTIMEOUT 0/' |
  @pinentry@ "$@"
