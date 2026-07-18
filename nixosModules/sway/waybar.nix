{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) gtklock sway;
  inherit (config.thoughtfull) user;
  inherit (lib) mkDefault mkIf;
  inherit (pkgs)
    bash
    curl
    font-awesome
    fuzzel
    iwmenu
    networkmanager
    networkmanagerapplet
    pasystray
    waybar
    wdisplays
    ;
  inherit (pkgs.thoughtfull)
    theme-toggle
    waybar-displays
    waybar-network
    waybar-yubikey
    ;
  power-menu = pkgs.thoughtfull.power-menu.override { gtklock = gtklock.package; };
  cfg = config.programs.waybar;
in
{
  environment = lib.mkIf sway.enable {
    etc = {
      "xdg/waybar/config.jsonc".source = ./waybar/config.jsonc;
      "xdg/waybar/style.css".source = ./waybar/style.css;
    };
    systemPackages = [
      font-awesome
      iwmenu
      networkmanager
      networkmanagerapplet
      pasystray
      power-menu
      waybar
      waybar-network
      waybar-yubikey
    ];
  };
  programs = {
    waybar = {
      enable = mkDefault sway.enable;
      systemd.target = mkDefault "sway-session.target";
    };
    yubikey-touch-detector = {
      enable = mkDefault sway.enable;
      libnotify = mkDefault false;
      verbose = mkDefault true;
    };
  };
  systemd = {
    # Workaround for yubikey-touch-detector GPG detection stopping after suspend/resume.
    # After resuming from suspend, GPG touch detection stops working while SSH and FIDO2
    # detection continue to work normally. Restarting the service fixes the issue.
    # This must be a system service (not user service) to properly hook into suspend/resume.
    # See: https://github.com/thoughtfull-nix/nixfiles/issues/139
    services.restart-yubikey-touch-detector = mkIf config.programs.yubikey-touch-detector.enable {
      description = "Restart YubiKey touch detector after resume";
      after = [ "suspend.target" ];
      wantedBy = [ "suspend.target" ];
      serviceConfig = {
        Type = "oneshot";
        # Use --machine to connect to the user's systemd instance and D-Bus session
        ExecStart = "${pkgs.systemd}/bin/systemctl --machine=${user.name}@.host --user restart yubikey-touch-detector.service";
      };
    };
    user.services = mkIf cfg.enable {
      pasystray = {
        after = [ "sway-session.target" ];
        bindsTo = [ "sway-session.target" ];
        enable = mkDefault sway.enable;
        wantedBy = [ "sway-session.target" ];
        serviceConfig = {
          ExecStart = "${pasystray}/bin/pasystray -N none";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };
      waybar = {
        # sway-session.target itself is ordered after gtk-defaults.service
        # (nixosModules/sway.nix), so waiting on the target alone already
        # guarantees the GTK theme is applied before this starts.
        after = [ "sway-session.target" ];
        path = [
          bash
          curl
          fuzzel
          gtklock.package
          iwmenu
          networkmanager
          networkmanagerapplet
          power-menu
          theme-toggle
          waybar-displays
          waybar-network
          waybar-yubikey
          wdisplays
        ];
      };
    };
  };
}
