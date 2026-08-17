#!@bash@

if [[ $1 == "--no-lock" ]]; then
  options="Logout\nSleep\nReboot\nShutdown"
else
  options="Lock\nLogout\nSleep\nReboot\nShutdown"
fi

selection=$(echo -e "$options" | @fuzzel@ --dmenu)

case "$selection" in
  Lock) @loginctl@ lock-session ;;
  Logout) @swaymsg@ exit ;;
  Sleep) @systemctl@ suspend ;;
  Reboot) @systemctl@ reboot ;;
  Shutdown) @systemctl@ poweroff ;;
esac
