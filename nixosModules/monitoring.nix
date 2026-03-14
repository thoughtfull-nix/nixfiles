{
  config,
  lib,
  pkgs,
  thoughtfull,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  inherit (pkgs) curl;
  inherit (thoughtfull.lib) writeFileScriptBin;
  cfg = config.thoughtfull.monitoring;

  alert-script = writeFileScriptBin {
    name = "ntfy";
    replacements = {
      curl = "${curl}/bin/curl";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      ntfyServer = cfg.ntfyServer;
      ntfyTopic = cfg.ntfyTopic;
    };
    src = ./monitoring/ntfy.bash;
  };
in
{
  config = mkIf cfg.enable {
    systemd.services = {
      "alert-on-failure@" = {
        description = "Send alert for failed unit %i";
        environment = {
          UNIT = "%i";
          HOST = "%H";
        };
        path = [ pkgs.bash ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${alert-script}/bin/ntfy";
        };
      };
    } // (lib.attrsets.genAttrs cfg.services (name: {
      onFailure = [ "alert-on-failure@%n.service" ];
    }));
  };

  options.thoughtfull.monitoring = {
    enable = mkEnableOption "systemd failure monitoring via ntfy";

    ntfyServer = mkOption {
      type = types.str;
      default = "https://ntfy.sh";
      description = "URL of the ntfy server";
    };

    ntfyTopic = mkOption {
      type = types.str;
      description = "Topic to publish alerts to";
    };

    services = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of systemd services to monitor for failures";
    };
  };
}
