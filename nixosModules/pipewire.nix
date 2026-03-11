{
  config,
  lib,
  ...
}:
let
  inherit (config.services) pipewire;
  inherit (lib) mkDefault;
in
{
  services.pipewire = {
    extraConfig.pipewire."99-disable-bell" = {
      # even though this looks like it is for X11, it works for Wayland
      "context.properties" = {
        "module.x11.bell" = false;
      };
    };
    pulse.enable = mkDefault pipewire.enable;
  };
}
