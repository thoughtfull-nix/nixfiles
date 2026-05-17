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
    auto-upgrade = callTest ./tests/auto-upgrade.nix;
    avahi = callTest ./tests/avahi.nix;
    github-token = callTest ./tests/github-token.nix;
    system-pull = callTest ./tests/system-pull.nix;
    waybar = callTest ./tests/waybar.nix;
  }
)
