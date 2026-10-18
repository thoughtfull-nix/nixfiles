# Lightweight nix eval check (not a nixosTest/VM boot) for sway.nix's GTK font
# defaults: gtk-defaults sets a real interface font (not a theme name), that
# font is visible to fontconfig, and GTK 4 renders text with manual
# (pixel-snapped) font rendering to avoid stray glyph pixels in text views.
# The gtk-defaults commands are also run against an in-memory gsettings
# backend, since they fail silently ("-" prefix) when schemas are missing.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  eval = nixosSystem {
    system = nixpkgs.stdenv.hostPlatform.system;
    lib = self.lib;
    modules = [
      { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
      ../nixosModules/sway.nix
      ../nixosModules/swayidle.nix
      stubs.graphicalEnable
      stubs.impermanence
      (
        { lib, ... }:
        {
          options.thoughtfull = {
            programs.mako.enable = lib.mkEnableOption "mako (stub)";
            user.name = lib.mkOption {
              type = lib.types.str;
              default = "testuser";
            };
          };
        }
      )
      { programs.sway.enable = true; }
    ];
  };

  inherit (eval) config;
  service = config.systemd.user.services.gtk-defaults;
  execStart = lib.concatStringsSep "\n" service.serviceConfig.ExecStart;
  has = needle: lib.hasInfix needle execStart;

  checks = [
    {
      name = "interface font is Adwaita Sans 11, not the Numix theme name";
      ok = has "font-name 'Adwaita Sans 11'" && !(has "font-name Numix");
    }
    {
      name = "Adwaita Sans is installed for fontconfig (fonts.packages)";
      ok = lib.any (p: (p.pname or "") == "adwaita-fonts") config.fonts.packages;
    }
    {
      name = "GTK font rendering is manual";
      ok = has "org.gnome.desktop.interface font-rendering manual";
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    sway test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  # Run each ExecStart against an in-memory backend with the service's own
  # environment, so a missing schema (or bad key/value) fails the build.
  nixpkgs.runCommand "sway-test"
    {
      env = removeAttrs service.environment [ "PATH" ] // {
        GSETTINGS_BACKEND = "memory";
      };
    }
    ''
      set -euo pipefail
      ${lib.concatMapStringsSep "\n" (lib.removePrefix "-") service.serviceConfig.ExecStart}
      touch $out
    ''
