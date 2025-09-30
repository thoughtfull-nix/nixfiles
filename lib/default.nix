self: {
  githubKeys = import ./github-keys.nix self;
  nixosConfiguration = import ./nixos-configuration.nix self;
}
