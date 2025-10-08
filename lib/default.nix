self@{ inputs, ... }:
let
  forEachSystem = with inputs.flake-utils.lib; eachSystemMap [ system.x86_64-linux ];
in
{
  githubKeys = import ./github-keys.nix self;
  inherit forEachSystem;
  nixosConfiguration = import ./nixos-configuration.nix self;
}
// forEachSystem (
  system:
  import ./nixpkgs (
    self
    // {
      pkgs = import inputs.nixpkgs {
        allowUnfree = true;
        inherit system;
      };
    }
  )
)
