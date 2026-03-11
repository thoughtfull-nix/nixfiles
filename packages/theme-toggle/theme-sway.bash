#!@bash@
set -euo pipefail

theme=$(@theme-get@)
if [[ $theme == dark ]]; then
  # Adwaita dark
  @swaymsg@ output \* bg /etc/sway/wallpaper-dark.svg fill
  @swaymsg@ client.focused_inactive '#5e5c64 #3d3846 #ffffff #5e5c64 #5e5c64'
  @swaymsg@ client.unfocused '#3d3846 #242424 #9a9996 #3d3846 #3d3846'
else
  # Adwaita light
  @swaymsg@ output \* bg /etc/sway/wallpaper-light.svg fill
  @swaymsg@ client.focused_inactive '#deddda #f6f5f4 #77767b #deddda #deddda'
  @swaymsg@ client.unfocused '#c0bfbc #deddda #3d3846 #c0bfbc #c0bfbc'
fi
