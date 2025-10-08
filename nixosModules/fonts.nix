{ lib, pkgs, ... }:
with lib;
{
  console = {
    earlySetup = mkDefault true;
    font = mkDefault "ter-116n";
    packages = [ pkgs.terminus_font ];
  };
}
