#!@bash@
set -euo pipefail

keyrings="${XDG_DATA_HOME:-$HOME/.local/share}/keyrings"
password="$keyrings/login.password.age"

if busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login \
  org.freedesktop.Secret.Collection Locked 2>/dev/null | grep -qx 'b false'; then
  exit 0
fi

if [[ ! -e $password ]]; then
  # The password would be new, so it couldn't unlock an existing keyring.
  if [[ -e $keyrings/login.keyring ]]; then
    message="$keyrings/login.keyring exists without $password; move it aside to start over"
    echo "$message" >&2
    notify-send -a gnome-keyring -u critical "Keyring not unlocked" "$message" || true
    exit 1
  fi
  recipients=()
  for recipient in $KEYRING_RECIPIENTS; do
    recipients+=(-r "$recipient")
  done
  install -d -m 0700 "$keyrings"
  head -c 32 /dev/urandom | base64 -w 0 | rage -e "${recipients[@]}" -o "$password.tmp"
  mv "$password.tmp" "$password"
fi

be32() {
  # shellcheck disable=SC2059
  printf "$(printf '\\x%02x' $(($1 >> 24 & 255)) $(($1 >> 16 & 255)) $(($1 >> 8 & 255)) $(($1 & 255)))"
}

notify-send -a gnome-keyring "Unlock keyring" "Enter your FIDO2 PIN, then touch your key" || true
secret=$(rage -d -j fido2-hmac "$password")
# `gnome-keyring-daemon --unlock` would start a second daemon, so unlock the running one the way
# pam_gnome_keyring does: a credentials byte, then length, op 1 (unlock), and the password.
reply=$({
  printf '\000'
  be32 $((12 + ${#secret}))
  be32 1
  be32 ${#secret}
  printf %s "$secret"
} | socat -t 5 - "UNIX-CONNECT:$XDG_RUNTIME_DIR/keyring/control" | od -An -tx1 | tr -d ' \n')
# length 8, result 0 (OK)
if [[ $reply != 0000000800000000 ]]; then
  echo "unlock failed: $reply" >&2
  exit 1
fi
