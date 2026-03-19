self@{
  inputs,
  lib,
  nixosModules,
  ...
}:
let
  inherit (builtins)
    hasAttr
    head
    listToAttrs
    match
    ;
  inherit (lib.thoughtfull) dirFiles;
  inherit (inputs.nixpkgs.lib) nixosSystem;
  kryptonix = inputs.kryptonix.nixosModules;
  loadConfiguration =
    file:
    let
      name = head (match "(.*)\.nix$" file);
      hostConfig = (import (./nixosConfigurations + "/${file}")) self;
    in
    {
      inherit name;
      value = nixosSystem {
        inherit (hostConfig) system;
        modules = [
          (nixosModules.default {
            inputs = inputs // {
              inherit self;
            };
          })
        ]
        ++ hostConfig.modules
        ++ (if hasAttr name kryptonix then [ kryptonix.${name} ] else [ ]);
        specialArgs = {
          inputs = inputs // {
            inherit self;
          };
        };
        # Use the extended lib from the flake
        lib = self.lib;
      };
    };
  configurations = dirFiles {
    dir = ./nixosConfigurations;
    excludes = [ "bootstrap.nix" ];
  };
in
listToAttrs (map loadConfiguration configurations)
