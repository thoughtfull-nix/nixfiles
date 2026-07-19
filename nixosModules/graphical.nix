{
  config,
  lib,
  ...
}:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkForce
    mkIf
    ;
in
{
  config = mkIf graphical.enable {
    gtk.iconCache.enable = mkDefault true;
    hardware.bluetooth.enable = mkDefault true;
    networking = {
      networkmanager = {
        enable = mkDefault true;
        # Wi-Fi is managed by iwd directly (iwmenu talks to iwd's D-Bus API,
        # bypassing NetworkManager) -- NetworkManager managing the same
        # device at the same time caused the two to race and repeatedly
        # fail to connect. NetworkManager still manages ethernet.
        #
        # This can't be mkDefault: nixpkgs' netbird module unconditionally
        # sets this (at normal priority, even when netbird is disabled) to
        # the netbird client interfaces, which is `[]` here since netbird
        # isn't used. listOf options merge by concatenating all definitions
        # at the winning priority tier, so a normal-priority `[]` from
        # netbird beats and discards an mkDefault entirely -- a plain
        # assignment here instead joins that tier, concatenating with it.
        unmanaged = [ "type:wifi" ];
      };
      # NetworkManager's module wants to enable this wpa_supplicant service
      # itself whenever its own wifi.backend isn't "iwd" (the default is
      # "wpa_supplicant"), which conflicts with wireless.iwd.enable below.
      # Deliberately not setting wifi.backend = "iwd" to avoid that: doing
      # so makes NetworkManager instantiate its own iwd manager (for every
      # iwd-backed interface it discovers, managed or not) which registers
      # itself as iwd's network-configuration D-Bus agent -- and then
      # rejects iwd's own DHCP requests for this unmanaged device with
      # "InvalidConnection", since NetworkManager never actually activates
      # it. iwd doesn't need NetworkManager involved in any way here.
      wireless.enable = mkForce false;
      wireless.iwd = {
        enable = mkDefault true;
        settings = {
          # NetworkManager no longer configures IP addresses for Wi-Fi
          # devices, so iwd has to do it itself.
          General.EnableNetworkConfiguration = mkDefault true;
          # Without this, sometimes wlan0 simply goes AWOL:
          # https://iwd.wiki.kernel.org/interface_lifecycle#interface_management_in_iwd
          # Normally NetworkManager's iwd backend sets this automatically,
          # but Wi-Fi is unmanaged by NetworkManager here, so it doesn't.
          DriverQuirks.DefaultInterface = mkDefault "?*";
          # iwd's own default (systemd, i.e. systemd-resolved) assumes
          # systemd-resolved is running. It isn't: this system resolves
          # DNS the classic way, via the resolvconf program (which is also
          # what NetworkManager uses for ethernet, by nixpkgs' default) --
          # so without this, Wi-Fi connects and gets an IP but
          # /etc/resolv.conf never gets a nameserver for it.
          Network.NameResolvingService = mkDefault "resolvconf";
        };
      };
    };
    programs = {
      firefox.enable = mkDefault true;
      sway.enable = mkDefault true;
    };
    services = {
      emacs.enable = mkDefault true;
      xremap.enable = mkDefault true;
    };
    systemd.user.services.mako.enable = mkDefault true;
    thoughtfull = {
      impermanence.user.directories = [ ".config/dconf" ];
      user.extraGroups = [ "networkmanager" ];
      programs = {
        dictation.enable = mkDefault true;
        obsidian.enable = mkDefault true;
      };
    };
  };
  options.thoughtfull.graphical.enable = mkEnableOption "graphical UI configuration";
}
