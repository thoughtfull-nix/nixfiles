self@{ inputs, ... }:
{
  forAllSystems = with inputs.nixpkgs.lib; genAttrs systems.flakeExposed;
  githubKeys = import ./github-keys.nix self;
  nixosConfiguration = import ./nixos-configuration.nix self;
}
