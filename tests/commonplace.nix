# Lightweight nix eval check (not a nixosTest/VM boot) for commonplace.nix:
# the package is installed, its library persisted, it handles commonplace:
# links, and sway binds a capture key when enabled.
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

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        { nixpkgs.overlays = [ self.inputs.vibes.overlays.default ]; }
        ../nixosModules/commonplace.nix
        impermanenceStub
        extraModule
      ];
    };

  enabled = mkEval { thoughtfull.programs.commonplace.enable = true; };
  disabled = mkEval { };
  withSway = mkEval {
    programs.sway.enable = true;
    thoughtfull.programs.commonplace.enable = true;
  };
  swayConf = eval: eval.config.environment.etc."sway/config.d/commonplace.conf" or null;
  hasCommonplace =
    eval: lib.any (p: (p.pname or "") == "commonplace") eval.config.environment.systemPackages;

  checks = [
    {
      name = "enabled: commonplace is installed";
      ok = hasCommonplace enabled;
    }
    {
      name = "enabled: commonplace library is persisted";
      ok = lib.elem ".local/share/commonplace" enabled.config.thoughtfull.impermanence.user.directories;
    }
    {
      name = "enabled: commonplace handles commonplace: links";
      ok =
        enabled.config.xdg.mime.defaultApplications."x-scheme-handler/commonplace" or null
        == "systems.thoughtfull.Commonplace.desktop";
    }
    {
      name = "enabled with sway: $mod+n captures a memo in a floating window";
      ok =
        let
          conf = builtins.readFile (swayConf withSway).source;
        in
        swayConf withSway != null
        && lib.hasInfix "bindsym $mod+n exec commonplace capture" conf
        && lib.hasInfix ''for_window [app_id="systems.thoughtfull.Commonplace" title="Capture"] floating enable'' conf;
    }
    {
      name = "enabled without sway: no sway config";
      ok = swayConf enabled == null;
    }
    {
      name = "disabled: commonplace is not installed";
      ok = !hasCommonplace disabled;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    commonplace test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "commonplace-test" { } "touch $out"
