{
  description = "Thoughtfull Systems nixfiles";
  inputs = {
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
