{ lib, pkgs, ... }:
let
  inherit (pkgs)
    bash
    fuzzel
    gawk
    jq
    makeDesktopItem
    networkmanager
    networkmanagerapplet
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
  waybar-network-wifi = writeFileScriptBin {
    name = "waybar-network-wifi";
    replacements = {
      bash = "${bash}/bin/bash";
      jq = "${jq}/bin/jq";
      network-device = "${network-device}/bin/waybar-network-device";
      nmcli = "${networkmanager}/bin/nmcli";
    };
    src = ./waybar-network/wifi-status.bash;
  };
  waybar-network-wifi-toggle = writeFileScriptBin {
    name = "waybar-network-wifi-toggle";
    replacements = {
      bash = "${bash}/bin/bash";
      network-device = "${network-device}/bin/waybar-network-device";
      nmcli = "${networkmanager}/bin/nmcli";
      systemctl = "${systemd}/bin/systemctl";
    };
    src = ./waybar-network/wifi-toggle.bash;
  };
  waybar-network-wifi-menu = writeFileScriptBin {
    name = "waybar-network-wifi-menu";
    replacements = {
      bash = "${bash}/bin/bash";
      fuzzel = "${fuzzel}/bin/fuzzel";
      network-device = "${network-device}/bin/waybar-network-device";
      "nm-connection-editor" = "${networkmanagerapplet}/bin/nm-connection-editor";
      nmcli = "${networkmanager}/bin/nmcli";
      systemctl = "${systemd}/bin/systemctl";
    };
    src = ./waybar-network/wifi-menu.bash;
  };
  waybar-network-wifi-menu-desktop = makeDesktopItem {
    name = "waybar-network-wifi-menu";
    desktopName = "Wi-Fi Networks";
    exec = "${waybar-network-wifi-menu}/bin/waybar-network-wifi-menu";
    icon = "network-wireless";
    terminal = false;
    type = "Application";
    categories = [ "Network" ];
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
  waybar-network-ethernet-menu = writeFileScriptBin {
    name = "waybar-network-ethernet-menu";
    replacements = {
      bash = "${bash}/bin/bash";
      fuzzel = "${fuzzel}/bin/fuzzel";
      "nm-connection-editor" = "${networkmanagerapplet}/bin/nm-connection-editor";
      nmcli = "${networkmanager}/bin/nmcli";
    };
    src = ./waybar-network/ethernet-menu.bash;
  };
  waybar-network-ethernet-menu-desktop = makeDesktopItem {
    name = "waybar-network-ethernet-menu";
    desktopName = "Ethernet Networks";
    exec = "${waybar-network-ethernet-menu}/bin/waybar-network-ethernet-menu";
    icon = "network-wired";
    terminal = false;
    type = "Application";
    categories = [ "Network" ];
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
    waybar-network-ethernet-menu
    waybar-network-ethernet-menu-desktop
    waybar-network-ethernet-toggle
    waybar-network-vpn
    waybar-network-vpn-toggle
    waybar-network-wifi
    waybar-network-wifi-menu
    waybar-network-wifi-menu-desktop
    waybar-network-wifi-toggle
  ];
}
