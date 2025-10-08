self@{ inputs, ... }:
{
  forEachSystem = with inputs.flake-utils.lib; eachSystemMap [ system.x86_64-linux ];
  githubKeys = import ./github-keys.nix self;
  nixosConfiguration = import ./nixos-configuration.nix self;
}
