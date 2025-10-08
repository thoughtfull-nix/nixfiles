{
  description = "Thoughtfull Systems nixfiles";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };
  outputs =
    { self, nixpkgs, ... }:
    {
      lib = import ./lib self;
      nixosConfigurations = import ./nixosConfigurations self;
      nixosModules = import ./nixosModules self;
      packages = self.lib.forEachSystem (
        system:
        let
          pkgs = import nixpkgs {
            allowUnfree = true;
            inherit system;
          };
        in
        import ./packages (self // { inherit pkgs; })
      );
    };
}
