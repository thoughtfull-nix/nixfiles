{ lib, pkgs, ... }:
{
  console = {
    earlySetup = lib.mkDefault true;
    font = lib.mkDefault "ter-116n";
    packages = [ pkgs.terminus_font ];
  };
}
