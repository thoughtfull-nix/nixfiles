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
in
{
  config = {
    age.secrets = mkIf vpn.enable {
      wg-quick-config.file = vpn.configFile;
    };
    networking.wg-quick.interfaces = mkIf vpn.enable {
      wg0 = {
        autostart = mkDefault vpn.autostart;
        configFile = secrets.wg-quick-config.path;
      };
    };
    systemd.services = mkIf vpn.enable {
      wg-quick-wg0.aliases = [ "vpn.service" ];
    };
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
