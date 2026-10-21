# Lightweight nix eval check (not a nixosTest/VM boot) for firefox.nix: the
# firefox-login unit doesn't set PATH, so firefox inherits the user manager's
# PATH and can hand URL schemes to apps whose desktop entries use TryExec.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  impermanenceStub =
    { lib, ... }:
    {
      options.thoughtfull.impermanence.user.directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

  eval = nixosSystem {
    system = nixpkgs.stdenv.hostPlatform.system;
    lib = self.lib;
    modules = [
      { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
      ../nixosModules/firefox.nix
      impermanenceStub
      {
        programs.firefox.enable = true;
        programs.sway.enable = true;
      }
    ];
  };
  unit = eval.config.systemd.user.units."firefox-login.service".text;

  checks = [
    {
      name = "firefox-login: unit is generated";
      ok = lib.hasInfix "ExecStart=" unit;
    }
    {
      name = "firefox-login: unit doesn't override PATH";
      ok = !lib.hasInfix "PATH=" unit;
    }
  ];
  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    firefox test failed:
    ${lib.concatMapStringsSep "\n" (c: "  - ${c.name}") failed}
  ''
else
  nixpkgs.runCommand "firefox-test" { } "touch $out"
