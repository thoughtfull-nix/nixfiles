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
let
  inherit (inputs)
    agenix
    disko
    impermanence
    kryptonix
    ;
in
(inputs.nixpkgs.lib.nixosSystem (
  args
  // {
    modules = modules ++ [
      (
        { config, lib, ... }:
        let
          inherit (config.thoughtfull) impermanence;
          inherit (lib) mkIf;
          system = config.nixpkgs.localSystem.system;
        in
        {
          environment.systemPackages = mkIf impermanence.disko.enable [
            disko.packages.${system}.disko
          ];
          imports = [ disko.nixosModules.default ];
        }
      )
      agenix.nixosModules.default
      impermanence.nixosModules.default
      kryptonix.nixosModules.default
      nixosModules.default
    ];
    specialArgs = specialArgs // {
      thoughtfull = {
        lib = lib // lib.${system};
        inherit nixosModules;
        pkgs = packages.${system};
      };
    };
  }
))
