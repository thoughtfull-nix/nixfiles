#!@bash@
# Wrapper script for gtklock that applies the current theme
set -euo pipefail

theme=$(@theme-get@)
if [[ $theme == dark ]]; then
  exec @gtklock@ -g Adwaita-dark -b /etc/sway/wallpaper-dark.svg "$@"
else
  exec @gtklock@ -g Adwaita -b /etc/sway/wallpaper-light.svg "$@"
fi
