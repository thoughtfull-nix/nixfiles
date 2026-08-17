{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (config.thoughtfull) user;
  inherit (lib) mkDefault mkIf;
  inherit (pkgs)
    bash
    curl
    font-awesome
    fuzzel
    networkmanager
    networkmanagerapplet
    pulseaudio
    systemd
    waybar
    wdisplays
    ;
  inherit (pkgs.thoughtfull)
    power-menu
    theme-toggle
    waybar-audio
    waybar-displays
    waybar-network
    waybar-yubikey
    ;
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
      networkmanager
      networkmanagerapplet
      power-menu
      waybar
      waybar-audio
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
      waybar = {
        # sway-session.target itself is ordered after gtk-defaults.service
        # (nixosModules/sway.nix), so waiting on the target alone already
        # guarantees the GTK theme is applied before this starts.
        after = [ "sway-session.target" ];
        # The packaged unit only carries PartOf=graphical-session.target, a
        # target this repo's sway integration never stops on logout (only
        # sway-session.target is stopped -- see nixosModules/sway/nixos.conf).
        # Without this, waybar survives logout still attached to the dying
        # session's Wayland socket, then dies once that socket actually
        # closes and respawns (Restart=on-failure) into a stale environment,
        # looping until systemd's start-limit kills it -- so it never comes
        # back on the next login. Same pattern as sway-autotiling/xremap in
        # nixosModules/sway.nix and kanshi in nixosModules/sway/kanshi.nix.
        bindsTo = [ "sway-session.target" ];
        path = [
          bash
          curl
          fuzzel
          networkmanager
          networkmanagerapplet
          power-menu
          pulseaudio
          systemd
          theme-toggle
          waybar-audio
          waybar-displays
          waybar-network
          waybar-yubikey
          wdisplays
        ];
      };
    };
  };
}
