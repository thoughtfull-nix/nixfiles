{ lib, ... }:
let
  inherit (lib) mkDefault;
in
{
  services.ntp.enable = mkDefault true;
}
