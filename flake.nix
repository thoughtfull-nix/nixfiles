{
  description = "Thoughtfull Systems nixfiles";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
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
