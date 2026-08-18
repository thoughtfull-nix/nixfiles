{ config, lib, ... }:
let
  inherit (config.programs) sway;
  cfg = config.thoughtfull.programs.sway.idle;
  inherit (lib)
    mkDefault
    mkOption
    types
    ;
  blankSeconds = cfg.lockSeconds + cfg.blankDelaySeconds;
in
{
  config.programs.swayidle = {
    enable = mkDefault sway.enable;
    # Lock after `lockSeconds` of inactivity, then blank the outputs
    # `blankDelaySeconds` later (turning them back on when resumed). Locking goes
    # through `loginctl lock-session` so it reaches the single lock.target path in
    # nixosModules/gtklock.nix -- shared with the lid, power-menu, and waybar
    # triggers -- rather than invoking gtklock directly. Locking *before sleep* is
    # handled synchronously by systemd-lock-handler (sleep.target
    # Requires=lock.target); a swayidle `before-sleep` would be redundant and, being
    # asynchronous, would race the suspend. On laptops, nixosModules/laptop.nix
    # replaces this whole config with a power-aware version (shorter on battery,
    # plus suspend).
    extraConfig = mkDefault ''
      timeout ${toString cfg.lockSeconds} 'loginctl lock-session'
      timeout ${toString blankSeconds} 'swaymsg "output * power off"' resume 'swaymsg "output * power on"'
    '';
  };
  options.thoughtfull.programs.sway.idle = {
    lockSeconds = mkOption {
      default = 900;
      description = "Seconds of inactivity before the screen locks (default 15 minutes).";
      type = types.ints.positive;
    };
    blankDelaySeconds = mkOption {
      default = 300;
      description = "Seconds after locking before the outputs power off (default 5 minutes).";
      type = types.ints.positive;
    };
  };
}
