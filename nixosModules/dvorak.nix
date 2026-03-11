{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkDefault mkIf;
in
{
  config = mkIf config.thoughtfull.dvorak.enable {
    console.useXkbConfig = mkDefault true;
    services.xserver.xkb = {
      layout = mkDefault "us";
      options = mkDefault "grp:shifts_toggle,ctrl:nocaps,compose:rctrl";
      variant = mkDefault "dvorak";
    };
  };
  options.thoughtfull.dvorak.enable = mkEnableOption "dvorak" // {
    default = true;
  };
}
