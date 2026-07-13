{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  inherit (pkgs) ntfy-sh;
  inherit (pkgs.thoughtfull) writeFileScriptBin;
  cfg = config.thoughtfull.monitoring;

  alert-script = writeFileScriptBin {
    name = "ntfy";
    replacements = {
      ntfy = "${ntfy-sh}/bin/ntfy";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      ntfyServer = cfg.ntfyServer;
      ntfyTopic = cfg.ntfyTopic;
    };
    src = ./monitoring/ntfy.bash;
  };

  ntfy-test-script = writeFileScriptBin {
    name = "ntfy-test";
    replacements = {
      ntfyServer = cfg.ntfyServer;
      ntfyTopic = cfg.ntfyTopic;
    };
    src = ./monitoring/ntfy-test.bash;
  };
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [
      ntfy-sh
      ntfy-test-script
    ];

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

      alert-on-failure-test = {
        description = "Test service that fails on purpose to exercise alert-on-failure";
        onFailure = [ "alert-on-failure@%n.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/false";
        };
      };
    }
    // (lib.attrsets.genAttrs cfg.services (_name: {
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
