# Lightweight nix eval check (not a nixosTest/VM boot) for graphical.nix's
# networking wiring: NetworkManager enabled and user-controllable, but with
# Wi-Fi handed off entirely to iwd (unmanaged by NetworkManager, its own IP
# configuration, no competing wpa_supplicant backend).
#
# A VM boot was considered and rejected: the original VM test's own node
# config wrote these config.* values into environment.etc files just so the
# testScript could `cat` them back out inside the VM -- a sign the values
# were already plain config, not runtime state, and readable directly here.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  # Stub options defined in other thoughtfull modules that graphical.nix sets via mkDefault
  graphicalDepsStub =
    { lib, ... }:
    {
      options = {
        services.restic.thoughtfull.enable = lib.mkEnableOption "restic (stub)";
        services.xremap.enable = lib.mkEnableOption "xremap (stub)";
        thoughtfull = {
          impermanence = {
            disko.enable = lib.mkEnableOption "impermanence disko (stub)";
            enable = lib.mkEnableOption "impermanence (stub)";
            user.directories = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
          monitoring = {
            enable = lib.mkEnableOption "monitoring (stub)";
            services = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
          programs = {
            dictation.enable = lib.mkEnableOption "dictation (stub)";
            obsidian.enable = lib.mkEnableOption "obsidian (stub)";
          };
          user.extraGroups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      };
    };

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
        ../nixosModules/graphical.nix
        graphicalDepsStub
        extraModule
      ];
    };

  enabled = mkEval (
    { lib, ... }:
    {
      thoughtfull.graphical.enable = true;
      # Disable heavy services irrelevant to this check
      hardware.bluetooth.enable = lib.mkForce false;
      programs.firefox.enable = lib.mkForce false;
      programs.sway.enable = lib.mkForce false;
      services.emacs.enable = lib.mkForce false;
      services.syncthing.enable = lib.mkForce false;
    }
  );
  disabled = mkEval { };
  # thoughtfull.graphical.enable defaults to false

  checks = [
    {
      name = "graphical enabled: NetworkManager is configured";
      ok = enabled.config.networking.networkmanager.enable;
    }
    {
      name = "graphical enabled: user can control NetworkManager";
      ok = lib.elem "networkmanager" enabled.config.thoughtfull.user.extraGroups;
    }
    {
      name = "graphical enabled: NetworkManager manages Wi-Fi directly, no iwd";
      ok =
        # Wi-Fi used to be carved out to iwd directly (unmanaged by
        # NetworkManager) because iwmenu talked to iwd's D-Bus API and the
        # two daemons fought over the same station if both were active (see
        # git history). iwmenu is gone -- the fuzzel Wi-Fi picker now talks
        # to NetworkManager via nmcli, the same as the Ethernet picker
        # already did -- so nothing needs to unmanage Wi-Fi or run iwd
        # anymore.
        #
        # networking.wireless.enable ends up true here regardless -- that's
        # nixpkgs' NetworkManager module itself enabling a dbus-controlled
        # wpa_supplicant service as its own default (non-iwd) backend, not
        # the standalone wpa_supplicant management iwd used to conflict
        # with, so it's not asserted on either way.
        !enabled.config.networking.wireless.iwd.enable
        && !(lib.elem "type:wifi" enabled.config.networking.networkmanager.unmanaged);
    }
    {
      name = "graphical disabled: NetworkManager is not configured";
      ok = !disabled.config.networking.networkmanager.enable;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    graphical test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "graphical-test" { } "touch $out"
