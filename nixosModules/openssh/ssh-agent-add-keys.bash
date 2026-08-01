#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob
keys=(
  "$HOME"/.ssh/*/*_auth_*
  "$HOME"/.ssh/*/*_sign_*
)

# Load keys one at a time so a token that's unplugged for one yubikey's stub
# doesn't stop later (reachable) keys from being attempted. Still exits
# nonzero -- and thus marks the unit "failed" -- if any key didn't load,
# rather than hiding that signal behind a blanket `|| true`.
status=0
for key in "${keys[@]}"; do
  [[ ${key} == *.pub ]] && continue
  ssh-add "$key" || status=1
done

exit "$status"
