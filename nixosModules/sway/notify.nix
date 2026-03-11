{
  config,
  lib,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (config.thoughtfull.programs) mako;
  inherit (lib)
    mkDefault
    mkIf
    ;
  keyBindings = ./notify/notify-key-bindings.conf;
in
{
  environment = mkIf mako.enable {
    etc."sway/config.d/notify-key-bindings.conf".source = keyBindings;
  };
  thoughtfull.programs.mako.enable = mkDefault sway.enable;
}
