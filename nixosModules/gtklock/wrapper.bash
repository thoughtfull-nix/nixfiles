#!@bash@
# Wrapper script for gtklock that applies the current theme
set -euo pipefail

echo "gtklock-wrapper[$$]: starting"

# swayidle can trigger gtklock from more than one place (idle timeout,
# before-sleep, manual lock) and these can race, e.g. the idle timeout firing
# again right after resume while a lock from before suspend is still up. Hold
# a non-blocking lock for our whole runtime so a second invocation just exits
# instead of queuing up another lock screen behind the first one.
lock_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gtklock-wrapper.lock"
exec 9>"$lock_file"
if ! @flock@ -n 9; then
  echo "gtklock-wrapper[$$]: $lock_file already held by another instance -- exiting without locking"
  exit 0
fi
echo "gtklock-wrapper[$$]: acquired $lock_file"

if ! @makoctl@ mode | grep -q dnd; then
  echo "gtklock-wrapper[$$]: mako not already in dnd mode -- enabling it for the duration of the lock"
  @makoctl@ mode -a dnd
  trap '@makoctl@ mode -r dnd' EXIT
else
  echo "gtklock-wrapper[$$]: mako already in dnd mode -- leaving it as-is"
fi

theme=$(@theme-get@)
echo "gtklock-wrapper[$$]: theme is $theme"
if [[ $theme == dark ]]; then
  @gtklock@ -g Adwaita-dark -b /etc/sway/wallpaper-dark.svg "$@"
else
  @gtklock@ -g Adwaita -b /etc/sway/wallpaper-light.svg "$@"
fi
echo "gtklock-wrapper[$$]: gtklock exited"
