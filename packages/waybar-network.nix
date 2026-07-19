{ lib, pkgs, ... }:
let
  inherit (pkgs)
    bash
    gawk
    jq
    networkmanager
    symlinkJoin
    systemd
    ;
  inherit (lib) writeFileScriptBin;
  network-device = writeFileScriptBin {
    name = "waybar-network-device";
    replacements = {
      awk = "${gawk}/bin/awk";
      bash = "${bash}/bin/bash";
      nmcli = "${networkmanager}/bin/nmcli";
    };
    src = ./waybar-network/network-device.bash;
  };
  wifi-device = writeFileScriptBin {
    name = "waybar-network-wifi-device";
    replacements = {
      bash = "${bash}/bin/bash";
      busctl = "${systemd}/bin/busctl";
      jq = "${jq}/bin/jq";
    };
    src = ./waybar-network/wifi-device.bash;
  };
  waybar-network-wifi = writeFileScriptBin {
    name = "waybar-network-wifi";
    replacements = {
      bash = "${bash}/bin/bash";
      jq = "${jq}/bin/jq";
      wifi-device = "${wifi-device}/bin/waybar-network-wifi-device";
    };
    src = ./waybar-network/wifi-status.bash;
  };
  waybar-network-wifi-toggle = writeFileScriptBin {
    name = "waybar-network-wifi-toggle";
    replacements = {
      bash = "${bash}/bin/bash";
      busctl = "${systemd}/bin/busctl";
      jq = "${jq}/bin/jq";
      wifi-device = "${wifi-device}/bin/waybar-network-wifi-device";
    };
    src = ./waybar-network/wifi-toggle.bash;
  };
  waybar-network-ethernet = writeFileScriptBin {
    name = "waybar-network-ethernet";
    replacements = {
      bash = "${bash}/bin/bash";
      network-device = "${network-device}/bin/waybar-network-device";
    };
    src = ./waybar-network/ethernet-status.bash;
  };
  waybar-network-ethernet-toggle = writeFileScriptBin {
    name = "waybar-network-ethernet-toggle";
    replacements = {
      bash = "${bash}/bin/bash";
      network-device = "${network-device}/bin/waybar-network-device";
      nmcli = "${networkmanager}/bin/nmcli";
    };
    src = ./waybar-network/ethernet-toggle.bash;
  };
  waybar-network-vpn = writeFileScriptBin {
    name = "waybar-network-vpn";
    replacements = {
      bash = "${bash}/bin/bash";
      systemctl = "${systemd}/bin/systemctl";
    };
    src = ./waybar-network/vpn-status.bash;
  };
  waybar-network-vpn-toggle = writeFileScriptBin {
    name = "waybar-network-vpn-toggle";
    replacements = {
      bash = "${bash}/bin/bash";
      systemctl = "${systemd}/bin/systemctl";
    };
    src = ./waybar-network/vpn-toggle.bash;
  };
in
symlinkJoin {
  name = "waybar-network";
  paths = [
    network-device
    waybar-network-ethernet
    waybar-network-ethernet-toggle
    waybar-network-vpn
    waybar-network-vpn-toggle
    waybar-network-wifi
    waybar-network-wifi-toggle
    wifi-device
  ];
}
