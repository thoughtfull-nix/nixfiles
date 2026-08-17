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
    nixpkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    callTest = path: import path { inherit self nixpkgs; };
  in
  {
    auto-upgrade = callTest ./tests/auto-upgrade.nix;
    avahi = callTest ./tests/avahi.nix;
    default = callTest ./tests/default.nix;
    dev = callTest ./tests/dev.nix;
    git = callTest ./tests/git.nix;
    github-token = callTest ./tests/github-token.nix;
    graphical = callTest ./tests/graphical.nix;
    gtklock = callTest ./tests/gtklock.nix;
    impermanence = callTest ./tests/impermanence.nix;
    kanshi = callTest ./tests/kanshi.nix;
    laptop = callTest ./tests/laptop.nix;
    minecraft-server = callTest ./tests/minecraft-server.nix;
    monitoring = callTest ./tests/monitoring.nix;
    nixfiles = callTest ./tests/nixfiles.nix;
    openssh = callTest ./tests/openssh.nix;
    restic = callTest ./tests/restic.nix;
    system-pull = callTest ./tests/system-pull.nix;
    user = callTest ./tests/user.nix;
    vpn = callTest ./tests/vpn.nix;
    waybar = callTest ./tests/waybar.nix;
  }
)
