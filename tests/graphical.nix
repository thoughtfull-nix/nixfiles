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
      name = "graphical enabled: iwd manages Wi-Fi directly, NetworkManager only manages ethernet";
      ok =
        # iwmenu (the Wi-Fi picker) talks to iwd's D-Bus API directly, so
        # NetworkManager must not also be driving the same wifi device -- the
        # two fighting over the same iwd station is what broke wifi in the
        # first place (see git history). NetworkManager keeps managing
        # ethernet.
        enabled.config.networking.wireless.iwd.enable
        && lib.elem "type:wifi" enabled.config.networking.networkmanager.unmanaged
        # NetworkManager's module wants to enable this wpa_supplicant service
        # itself whenever wifi.backend isn't "iwd" (deliberately not set here
        # -- see graphical.nix for why), which would conflict with
        # wireless.iwd.enable and break the build (`Only one wireless daemon
        # is allowed at the time`).
        && !enabled.config.networking.wireless.enable
        # iwd does its own IP configuration now that NetworkManager isn't
        # managing the wifi device to run DHCP for it.
        && enabled.config.networking.wireless.iwd.settings.General.EnableNetworkConfiguration;
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
