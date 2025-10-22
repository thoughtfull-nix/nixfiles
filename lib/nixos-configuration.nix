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
      inherit inputs;
      thoughtfull = {
        inherit nixosModules;
        lib = lib // lib.${system};
        pkgs = packages.${system};
      };
    };
  }
))
