self@{ inputs, ... }:
let
  inherit (inputs.flake-utils.lib) eachSystemMap system;
  inherit (inputs.nixpkgs.lib)
    concatMap
    getValues
    isFunction
    mkOptionType
    ;
  forEachSystem = eachSystemMap [ system.x86_64-linux ];
in
{
  inherit forEachSystem;
  dirFiles = import ./lib/dir-files.nix self;
  dirPaths = import ./lib/dir-paths.nix self;
  githubKeys = import ./lib/github-keys.nix self;
  # selectorFunction taken from home-manager
  types.selectorFunction = mkOptionType {
    name = "selectorFunction";
    description =
      "Function that takes an attribute set and returns a list"
      + " containing a selection of the values of the input set";
    check = isFunction;
    merge =
      _loc: defs: as:
      concatMap (select: select as) (getValues defs);
  };
}
