{ lib, ... }:
with lib;
{
  asaph = nixosConfiguration {
    modules = [ (import ./asaph) ];
    system = "x86_64-linux";
  };
  nixos = nixosConfiguration {
    modules = [ (import ./nixos.nix) ];
    system = "x86_64-linux";
  };
}
