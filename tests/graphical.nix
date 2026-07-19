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
      { config, lib, ... }:
      {
        inherit imports;
        thoughtfull.graphical.enable = true;
        # Disable heavy services to keep the test VM lightweight
        hardware.bluetooth.enable = lib.mkForce false;
        programs.firefox.enable = lib.mkForce false;
        programs.sway.enable = lib.mkForce false;
        services.emacs.enable = lib.mkForce false;
        services.syncthing.enable = lib.mkForce false;
        environment.etc."thoughtfull-user-extra-groups".text =
          builtins.concatStringsSep "\n" config.thoughtfull.user.extraGroups;
        environment.etc."networkmanager-unmanaged".text =
          builtins.concatStringsSep "\n" config.networking.networkmanager.unmanaged;
        environment.etc."wireless-enable".text = lib.boolToString config.networking.wireless.enable;
        environment.etc."iwd-enable-network-configuration".text =
          lib.boolToString config.networking.wireless.iwd.settings.General.EnableNetworkConfiguration;
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

    with subtest("graphical enabled: user can control NetworkManager"):
        enabled.succeed("grep -Fx networkmanager /etc/thoughtfull-user-extra-groups")

    with subtest(
        "graphical enabled: iwd manages Wi-Fi directly, NetworkManager only manages ethernet"
    ):
        # iwmenu (the Wi-Fi picker) talks to iwd's D-Bus API directly, so
        # NetworkManager must not also be driving the same wifi device --
        # the two fighting over the same iwd station is what broke wifi in
        # the first place (see git history). NetworkManager keeps managing
        # ethernet.
        enabled.succeed("systemctl cat iwd.service")
        enabled.succeed("grep -Fx type:wifi /etc/networkmanager-unmanaged")
        # NetworkManager's module wants to enable this wpa_supplicant
        # service itself whenever wifi.backend isn't "iwd" (deliberately
        # not set here -- see graphical.nix for why), which would conflict
        # with wireless.iwd.enable and break the build (`Only one wireless
        # daemon is allowed at the time`).
        enabled.succeed("grep -Fx false /etc/wireless-enable")
        # iwd does its own IP configuration now that NetworkManager isn't
        # managing the wifi device to run DHCP for it.
        enabled.succeed("grep -Fx true /etc/iwd-enable-network-configuration")

    with subtest("graphical disabled: NetworkManager is not configured"):
        disabled.fail("systemctl cat NetworkManager.service")
  '';
}
