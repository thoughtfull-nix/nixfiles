self@{ inputs, lib, ... }:
let
  inherit (builtins)
    hasAttr
    head
    listToAttrs
    match
    ;
  inherit (lib) dirFiles nixosConfiguration;
  kryptonix = inputs.kryptonix.nixosModules;
  loadConfiguration =
    file:
    let
      name = head (match "(.*)\.nix$" file);
      config = (nixosConfiguration ((import (./nixosConfigurations + "/${file}")) self));
    in
    {
      inherit name;
      value = config.extendModules {
        modules = if hasAttr name kryptonix then [ kryptonix.${name} ] else [ ];
      };
    };
  configurations = dirFiles {
    dir = ./nixosConfigurations;
    excludes = [ "bootstrap.nix" ];
  };
in
listToAttrs (map loadConfiguration configurations)
