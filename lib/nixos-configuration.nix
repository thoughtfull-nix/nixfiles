{
  inputs,
  lib,
  nixosModules,
  packages,
  ...
}:
args@{
  modules ? [ ],
  specialArgs ? { },
  system,
  ...
}:
(inputs.nixpkgs.lib.nixosSystem (
  args
  // {
    modules = modules ++ [ nixosModules.default ];
    specialArgs = specialArgs // {
      inherit (inputs) nixpkgs;
      thoughtfull = {
        inherit lib nixosModules;
        packages = packages.${system};
      };
    };
  }
))
