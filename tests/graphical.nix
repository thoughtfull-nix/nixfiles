{ nixpkgs, self, ... }:
let
  overlayModule = {
    nixpkgs.overlays = [ self.overlays.thoughtfull ];
  };

  # Stub options defined in other thoughtfull modules that graphical.nix sets via mkDefault
  graphicalDepsStub =
    { lib, ... }:
    {
      options = {
        services.restic.thoughtfull.enable = lib.mkEnableOption "restic (stub)";
        services.xremap.enable = lib.mkEnableOption "xremap (stub)";
        thoughtfull = {
          backlight.enable = lib.mkEnableOption "backlight (stub)";
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

  imports = [
    ../nixosModules/graphical.nix
    graphicalDepsStub
    overlayModule
  ];
in
nixpkgs.testers.nixosTest {
  name = "graphical";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    enabled =
      { lib, ... }:
      {
        inherit imports;
        thoughtfull.graphical.enable = true;
        # Disable heavy services to keep the test VM lightweight
        hardware.bluetooth.enable = lib.mkForce false;
        programs.firefox.enable = lib.mkForce false;
        programs.sway.enable = lib.mkForce false;
        services.emacs.enable = lib.mkForce false;
        services.syncthing.enable = lib.mkForce false;
      };

    disabled = {
      inherit imports;
      # thoughtfull.graphical.enable defaults to false
    };
  };

  testScript = ''
    start_all()
    enabled.wait_for_unit("multi-user.target")
    disabled.wait_for_unit("multi-user.target")

    with subtest("graphical enabled: NetworkManager is configured"):
        enabled.succeed("systemctl cat NetworkManager.service")

    with subtest("graphical disabled: NetworkManager is not configured"):
        disabled.fail("systemctl cat NetworkManager.service")
  '';
}
