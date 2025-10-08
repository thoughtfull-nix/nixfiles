{ lib, ... }:
with lib;
{
  console.useXkbConfig = mkDefault true;
  services.xserver.xkb = {
    layout = mkDefault "us";
    options = mkDefault "grp:shifts_toggle,ctrl:nocaps,compose:rctrl";
    variant = mkDefault "dvorak";
  };
}
