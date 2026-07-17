{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (config.thoughtfull) graphical;
  inherit (lib)
    mkIf
    mkDefault
    mkForce
    ;
  inherit (pkgs)
    adw-gtk3
    adwaita-fonts
    autotiling
    glib
    gnome-backgrounds
    gnome-themes-extra
    hyprpicker
    libadwaita
    numix-cursor-theme
    numix-icon-theme
    sound-theme-freedesktop
    xdg-desktop-portal-gtk
    ;
  inherit (pkgs.thoughtfull)
    brightness
    mic
    speaker
    theme-toggle
    ;
in
{
  environment = mkIf sway.enable {
    etc = (import ./sway/config.d { dirFiles = lib.thoughtfull.dirFiles; }) // {
      "sway/config.d/nixos.conf".source = mkForce ./sway/nixos.conf;
      "sway/config".source = ./sway/config;
      "sway/wallpaper-dark.svg".source = "${gnome-backgrounds}/share/backgrounds/gnome/drool-d.svg";
      "sway/wallpaper-light.svg".source = "${gnome-backgrounds}/share/backgrounds/gnome/drool-l.svg";
    };
    loginShellInit = ''
      # If running from tty1 start sway
      [ "$(tty)" = "/dev/tty1" ] && \
          echo "=== $(date)" >>sway.log && \
          exec ${sway.package}/bin/sway &>>sway.log
    '';
    sessionVariables.SSH_ASKPASS_REQUIRE = "prefer";
    systemPackages = [
      adw-gtk3
      adwaita-fonts
      brightness
      glib
      gnome-backgrounds
      # needed for Adwaita-dark theme
      gnome-themes-extra
      hyprpicker
      libadwaita
      mic
      numix-cursor-theme
      numix-icon-theme
      sound-theme-freedesktop
      speaker
      theme-toggle
    ];
  };
  imports = [
    ./sway/idle.nix
    ./sway/kanshi.nix
    ./sway/notify.nix
    ./sway/waybar.nix
  ];
  programs = {
    dconf.enable = mkDefault sway.enable;
    gtklock.enable = mkDefault sway.enable;
    sway = {
      enable = mkDefault graphical.enable;
      # sway adds foot, but I want to use my wrapper for theming
      extraPackages = mkForce [ ];
      wrapperFeatures.gtk = true;
    };
  };
  thoughtfull.impermanence.user.files = mkIf sway.enable [ ".config/theme" ];
  services.gnome = {
    # Conflicts with programs.ssh.startAgent
    gcr-ssh-agent.enable = false;
    gnome-keyring.enable = true;
    gnome-settings-daemon.enable = mkDefault sway.enable;
  };
  systemd.user.services = {
    gtk-defaults = {
      after = [ "sway-session.target" ];
      # partOf (not bindsTo): this unit must never *pull up* sway-session.target
      # by being restarted (see the exec_always in sway/config) -- only follow
      # it down when the session itself stops/restarts.
      partOf = [ "sway-session.target" ];
      enable = mkDefault sway.enable;
      wantedBy = [ "sway-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        # Keeps `systemctl --user status` showing active/exited instead of
        # inactive (dead) after this ad-hoc-restarted unit runs, so it doesn't
        # look like it never ran or failed when debugging theming issues.
        RemainAfterExit = true;
        # sway reruns this on every config reload via `systemctl --user restart
        # gtk-defaults.service`, so waybar (ordered `after` this unit) never
        # starts before the GTK icon/cursor/font theme is actually applied.
        # Each command is "-"-prefixed so one failure doesn't skip the rest.
        ExecStart = mkDefault [
          "-${glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme Adwaita"
          "-${glib}/bin/gsettings set org.gnome.desktop.interface icon-theme Numix"
          "-${glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme Numix"
          "-${glib}/bin/gsettings set org.gnome.desktop.interface cursor-size 32"
          "-${glib}/bin/gsettings set org.gnome.desktop.interface font-name Numix"
        ];
      };
    };
    sway-autotiling = {
      after = [ "sway-session.target" ];
      bindsTo = [ "sway-session.target" ];
      enable = mkDefault sway.enable;
      wantedBy = [ "sway-session.target" ];
      serviceConfig.ExecStart = mkDefault "${autotiling}/bin/autotiling";
    };
    xremap = {
      after = [ "sway-session.target" ];
      bindsTo = [ "sway-session.target" ];
      enable = mkDefault sway.enable;
      wantedBy = [ "sway-session.target" ];
    };
  };
  xdg.portal = {
    enable = mkDefault sway.enable;
    extraPortals = [ xdg-desktop-portal-gtk ];
    wlr.enable = mkDefault sway.enable;
  };
}
