{ dirFiles, ... }:
let
  inherit (builtins) listToAttrs;
  files = dirFiles {
    dir = ./.;
    excludes = [ "default.nix" ];
  };
in
listToAttrs (
  map (n: {
    name = "sway/config.d/${n}";
    value = {
      source = ./${n};
    };
  }) files
)
