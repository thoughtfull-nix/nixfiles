{ config, ... }:
let
  inherit (config.programs) sway;
in
{
  config.programs.swayidle = {
    enable = sway.enable;
    extraConfig = ''
      # This will lock your screen after 600 seconds (10 minutes) of inactivity, then turn off
      # your displays after another 600 seconds, and turn your screens back on when resumed. It
      # will also lock your screen before your computer goes to sleep.
      #
      # Locking goes through `loginctl lock-session` rather than invoking gtklock directly, same
      # as the waybar lock button and power-menu's Lock entry (see nixosModules/gtklock.nix) --
      # that's what arms nixosModules/laptop.nix's battery-lock-suspend timer, so an idle-timeout
      # lock on battery still auto-suspends even though nothing closed the lid.
      timeout 600 'loginctl lock-session'
      timeout 1200 'swaymsg "output * power off"' resume 'swaymsg "output * power on"'
      before-sleep 'loginctl lock-session'
    '';
  };
}
