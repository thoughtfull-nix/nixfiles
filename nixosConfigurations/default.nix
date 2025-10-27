{ lib, ... }:
with lib;
{
  beninu = nixosConfiguration {
    modules = [ (import ./beninu) ];
    system = "x86_64-linux";
  };
  nixos = nixosConfiguration {
    modules = [ (import ./nixos.nix) ];
    system = "x86_64-linux";
  };
}
