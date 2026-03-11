{
  description = "Thoughtfull Systems nixfiles";
  inputs = {
    agenix = {
      inputs = {
        darwin.follows = "";
        home-manager.follows = "";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
      url = "github:ryantm/agenix";
    };
    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko";
    };
    flake-utils = {
      inputs.systems.follows = "systems";
      url = "github:numtide/flake-utils";
    };
    impermanence = {
      inputs = {
        nixpkgs.follows = "";
        home-manager.follows = "";
      };
      url = "github:nix-community/impermanence";
    };
    kryptonix.url = "git+ssh://git@github.com/technosophist/kryptonix?ref=sedna";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default";
  };
  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      inherit (self) packages;
      inherit (self.lib) forEachSystem;
    in
    {
      emacsPackages = import ./emacsPackages.nix self;
      lib = import ./lib.nix self;
      nixosConfigurations = import ./nixosConfigurations.nix self;
      nixosModules = import ./nixosModules.nix self;
      overlays = import ./overlays.nix self;
      packages = forEachSystem (
        system:
        import ./packages.nix (
          self
          // {
            lib = self.lib // self.lib.${system};
            pkgs =
              import nixpkgs {
                allowUnfree = true;
                inherit system;
              }
              // packages.${system};
          }
        )
      );
    };
}
