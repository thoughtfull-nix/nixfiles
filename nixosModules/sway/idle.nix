{ config, ... }:
let
  inherit (config.programs) gtklock sway;
in
{
  config.programs.swayidle = {
    enable = sway.enable;
    extraConfig = ''
      # This will lock your screen after 600 seconds (10 minutes) of inactivity, then turn off
      # your displays after another 600 seconds, and turn your screens back on when resumed. It
      # will also lock your screen before your computer goes to sleep.
      timeout 600 '${gtklock.package}/bin/gtklock &'
      timeout 1200 'swaymsg "output * power off"' resume 'swaymsg "output * power on"'
      before-sleep '${gtklock.package}/bin/gtklock'
    '';
  };
}
