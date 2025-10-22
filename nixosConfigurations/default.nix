{ lib, ... }:
with lib;
{
  nixos = nixosConfiguration {
    modules = [ (import ./nixos.nix) ];
    system = "x86_64-linux";
  };
}
