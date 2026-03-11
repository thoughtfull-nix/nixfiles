{ config, lib, ... }:
let
  inherit (lib) mkDefault;
in
{
  services.printing.enable = mkDefault config.thoughtfull.graphical.enable;
}
