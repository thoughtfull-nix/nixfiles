{ lib, ... }:
let
  inherit (lib) mkDefault;
in
{
  services.avahi = {
    enable = mkDefault true;
    nssmdns4 = mkDefault true;
    publish = {
      addresses = mkDefault true;
      domain = mkDefault true;
      enable = mkDefault true;
    };
  };
}
