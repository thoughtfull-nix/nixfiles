{ lib, ... }:
with lib;
{
  mehida = nixosConfiguration {
    modules = [ (import ./mehida.nix) ];
    system = "x86_64-linux";
  };
}
