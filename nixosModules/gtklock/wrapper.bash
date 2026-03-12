#!@bash@
# Wrapper script for gtklock that applies the current theme
set -euo pipefail

if ! @makoctl@ mode | grep -q dnd; then
  @makoctl@ mode -a dnd
  trap '@makoctl@ mode -r dnd' EXIT
fi

theme=$(@theme-get@)
if [[ $theme == dark ]]; then
  @gtklock@ -g Adwaita-dark -b /etc/sway/wallpaper-dark.svg "$@"
else
  @gtklock@ -g Adwaita -b /etc/sway/wallpaper-light.svg "$@"
fi
