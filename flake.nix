{
  description = "Thoughtfull Systems nixfiles";
  inputs = {
    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko/v1.11.0";
    };
    impermanence.url = "github:nix-community/impermanence";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };
  outputs =
    { self, ... }:
    {
      lib = import ./lib self;
      nixosConfigurations = import ./nixosConfigurations self;
      nixosModules = import ./nixosModules self;
      packages = import ./packages self;
    };
}
