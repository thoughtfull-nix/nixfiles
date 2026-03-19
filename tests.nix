self@{
  inputs,
  ...
}:
let
  customLib = import ./lib.nix self;
  inherit (customLib) forEachSystem;
in
forEachSystem (
  system:
  let
    nixpkgs = inputs.nixpkgs.legacyPackages.${system};
    callTest = path: import path { inherit self nixpkgs; };
  in
  {
    avahi = callTest ./tests/avahi.nix;
    waybar = callTest ./tests/waybar.nix;
  }
)
