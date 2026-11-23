# Lightweight nix eval check (not a nixosTest/VM boot) for screenshot.nix:
# flameshot should capture with grim on wlroots and not pop up notifications
# about it on every capture.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  eval = nixosSystem {
    system = nixpkgs.stdenv.hostPlatform.system;
    lib = self.lib;
    modules = [
      ../nixosModules/screenshot.nix
      stubs.graphicalEnable
      stubs.impermanence
      {
        thoughtfull.graphical.enable = true;
        programs.sway.enable = true;
      }
    ];
  };
  ini = lib.splitString "\n" (eval.config.environment.etc."xdg/flameshot/flameshot.ini".text or "");

  checks = [
    {
      name = "flameshot ini has a [General] section";
      ok = lib.elem "[General]" ini;
    }
    {
      name = "flameshot uses the grim adapter";
      ok = lib.elem "useGrimAdapter=true" ini;
    }
    {
      name = "flameshot doesn't warn about grim";
      ok = lib.elem "disabledGrimWarning=true" ini;
    }
  ];
  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    screenshot test failed:
    ${lib.concatMapStringsSep "\n" (c: "  - ${c.name}") failed}
  ''
else
  nixpkgs.runCommand "screenshot-test" { } "touch $out"
