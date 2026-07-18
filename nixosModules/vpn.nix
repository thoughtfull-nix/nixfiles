{ config, lib, ... }:
let
  inherit (config.age) secrets;
  inherit (config.thoughtfull) vpn;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  # Single source of truth for the wg-quick interface name, so the systemd
  # unit it implies can't drift out of sync between the aliases line and the
  # polkit rule below. systemd.services attrset keys are bare unit names
  # (NixOS appends ".service"); the polkit rule needs the full unit id.
  iface = "wg0";
  serviceName = "wg-quick-${iface}";
  unit = "${serviceName}.service";
in
{
  config = {
    age.secrets = mkIf vpn.enable {
      wg-quick-config.file = vpn.configFile;
    };
    networking.wg-quick.interfaces = mkIf vpn.enable {
      ${iface} = {
        autostart = mkDefault vpn.autostart;
        configFile = secrets.wg-quick-config.path;
      };
    };
    systemd.services = mkIf vpn.enable {
      ${serviceName}.aliases = [ "vpn.service" ];
    };
    # Lets a non-root user (e.g. the waybar-network-vpn-toggle widget) start
    # and stop the VPN without a password prompt, scoped to exactly this
    # unit rather than a blanket systemd grant.
    security.polkit.enable = mkIf vpn.enable (mkDefault true);
    # Not mkDefault: types.lines drops mkDefault-priority definitions
    # entirely whenever another module sets this option at normal priority
    # (e.g. networking.networkmanager's own extraConfig, enabled on every
    # graphical host per nixosModules/graphical.nix) -- it doesn't merge in
    # at lower precedence the way mkDefault does for single-value options.
    security.polkit.extraConfig = mkIf vpn.enable ''
      polkit.addRule(function(action, subject) {
        var unit = action.lookup("unit");
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            (unit == "${unit}" || unit == "vpn.service") &&
            subject.isInGroup("wheel")) {
          return polkit.Result.YES;
        }
      });
    '';
  };
  options.thoughtfull.vpn = {
    autostart = mkOption {
      default = false;
      type = types.bool;
    };
    configFile = mkOption {
      default = null;
      type = types.nullOr types.path;
    };
    enable = mkEnableOption "thoughtfull vpn" // {
      default = vpn.configFile != null;
    };
  };
}
