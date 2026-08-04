#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob
keys=(
  "$HOME"/.ssh/*/*_auth_*
  "$HOME"/.ssh/*/*_sign_*
)

if loaded="$(ssh-add -L 2>/dev/null)"; then :; else loaded=""; fi

# ssh-add doesn't check whether a key is already loaded before re-adding it,
# so without this a touch/PIN-protected key already in the agent would get
# prompted again on every run (mirrors git/git-signing-key.bash's own
# ssh-add -L check). Compares against the key's already-committed .pub
# companion rather than deriving one from the private key file, so this
# never depends on that file being present/readable/well-formed.
already_loaded() {
  local pub
  pub="$(cat "${1}.pub" 2>/dev/null)" || return 1
  # -n "$pub" matters, not just -n "$loaded": grep -qF against an empty
  # pattern matches any non-empty input, so an empty/unreadable .pub
  # companion would otherwise read as "already loaded" -- silently and
  # permanently skipping a key that was never actually added -- as soon as
  # the agent has any other identity loaded at all.
  [[ -n ${pub} && -n ${loaded} ]] && grep -qF "$(cut -d' ' -f1-2 <<<"${pub}")" <<<"${loaded}"
}

# Load keys one at a time so a token that's unplugged for one yubikey's stub
# doesn't stop later (reachable) keys from being attempted. Still exits
# nonzero -- and thus marks the unit "failed" -- if any key didn't load,
# rather than hiding that signal behind a blanket `|| true`.
status=0
for key in "${keys[@]}"; do
  [[ ${key} == *.pub ]] && continue
  already_loaded "$key" && continue
  ssh-add "$key" || status=1
done

exit "$status"
