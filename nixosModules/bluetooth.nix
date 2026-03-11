{ config, lib, ... }:
let
  inherit (config.hardware) bluetooth;
  inherit (lib) mkDefault;
in
{
  services = {
    blueman.enable = mkDefault bluetooth.enable;
    # enable codecs for bluetooth audio
    pipewire.wireplumber.extraConfig."10-bluez" = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [
          "hsp_hs"
          "hsp_ag"
          "hfp_hf"
          "hfp_ag"
        ];
      };
    };
  };
  systemd.user.services.blueman-applet = {
    after = [
      "graphical-session.target"
      "sway-session.target"
    ];
    wantedBy = [
      "graphical-session.target"
      "sway-session.target"
    ];
  };
}
