#!/usr/bin/env bash
sudo loadkeys dvorak
dumpkeys | sed 's/Caps_Lock/Control/' | sudo loadkeys
nix run --refresh \
  --extra-experimental-features 'nix-command flakes' \
  "github:thoughtfull-nix/nixfiles/${BOOTSTRAP_GIT_BRANCH:-main}#nixfiles" -- \
  provision \
  "$@"
