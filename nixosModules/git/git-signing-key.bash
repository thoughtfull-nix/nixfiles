#!/usr/bin/env bash
set -euo pipefail

primary="@primary@"
backup="@backup@"

if loaded="$(ssh-add -L 2>/dev/null)"; then :; else loaded=""; fi

matches() {
  [[ -n $loaded ]] && grep -qF "$(cut -d' ' -f1-2 <<<"$1")" <<<"$loaded"
}

if matches "$primary"; then
  echo "key::$primary"
elif [[ -n $backup ]] && matches "$backup"; then
  echo "key::$backup"
else
  echo "git-signing-key: no configured signing key is loaded in ssh-agent (insert the primary or backup YubiKey)" >&2
  exit 1
fi
