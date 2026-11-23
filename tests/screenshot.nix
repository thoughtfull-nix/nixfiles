# Lightweight nix eval check (not a nixosTest/VM boot) for screenshot.nix:
# flameshot should capture with grim on sway and not pop up notifications
# about it on every capture.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  evalWith =
    swayEnable:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        ../nixosModules/screenshot.nix
        stubs.graphicalEnable
        stubs.impermanence
        {
          thoughtfull.graphical.enable = true;
          programs.sway.enable = swayEnable;
        }
      ];
    };
  etc = (evalWith true).config.environment.etc;
  etcNoSway = (evalWith false).config.environment.etc;
  ini = lib.splitString "\n" (etc."xdg/flameshot/flameshot.ini".text or "");

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
    {
      # the grim adapter only works on wlroots compositors
      name = "flameshot ini is not installed without sway";
      ok = !(etcNoSway ? "xdg/flameshot/flameshot.ini");
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
