#!@bash@
# Wrapper that applies the current theme before launching gtklock and silences
# notifications (mako do-not-disturb) while locked. gtklock is started only by
# gtklock-session-lock.service (nixosModules/gtklock.nix), which systemd keeps to
# a single instance -- so no cross-invocation deduplication is needed here.
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
