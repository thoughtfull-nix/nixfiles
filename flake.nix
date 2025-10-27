{
  description = "Thoughtfull Systems nixfiles";
  inputs = {
    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko/v1.12.0";
    };
    flake-utils.url = "github:numtide/flake-utils";
    impermanence.url = "github:nix-community/impermanence/4b3e914cdf97a5b536a889e939fb2fd2b043a170";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };
  outputs =
    { nixpkgs, self, ... }:
    rec {
      lib = import ./lib self;
      nixosConfigurations = import ./nixosConfigurations self;
      nixosModules = import ./nixosModules;
      packages = lib.forEachSystem (
        system:
        import ./packages (
          self
          // {
            pkgs = import nixpkgs {
              allowUnfree = true;
              inherit system;
            };
            lib = lib // lib.${system};
          }
        )
      );
    };
}
