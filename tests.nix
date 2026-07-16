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
    default = callTest ./tests/default.nix;
    dev = callTest ./tests/dev.nix;
    github-token = callTest ./tests/github-token.nix;
    graphical = callTest ./tests/graphical.nix;
    kanshi = callTest ./tests/kanshi.nix;
    monitoring = callTest ./tests/monitoring.nix;
    nixfiles = callTest ./tests/nixfiles.nix;
    system-pull = callTest ./tests/system-pull.nix;
    waybar = callTest ./tests/waybar.nix;
  }
)
