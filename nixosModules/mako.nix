{
  config,
  lib,
  pkgs,
  thoughtfull,
  ...
}:
let
  inherit (config.thoughtfull.programs) mako;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  inherit (pkgs)
    libnotify
    mpv
    replaceVars
    ;
  inherit (thoughtfull.lib) writeFileScriptBin;
  makoDismiss = writeFileScriptBin {
    name = "mako-dismiss";
    src = ./mako/dismiss.bash;
  };
  makoToggleDnd = writeFileScriptBin {
    name = "mako-toggle-dnd";
    src = ./mako/toggle-dnd.bash;
  };
  makoConfig = replaceVars ./mako/config {
    notify = ./mako/notify.ogg;
  };
in
{
  config = {
    environment = {
      systemPackages = mkIf mako.enable [
        libnotify
        mako.package
        makoDismiss
        makoToggleDnd
      ];
    };
    systemd.user.services.mako = {
      after = [ "graphical-session.target" ];
      description = "Lightweight Wayland notification daemon";
      documentation = [ "man:mako(1)" ];
      enable = mkDefault mako.enable;
      partOf = [ "graphical-session.target" ];
      path = [ mpv ];
      serviceConfig = {
        BusName = "org.freedesktop.Notifications";
        ExecCondition = "/bin/sh -c '[ -n \"$WAYLAND_DISPLAY\" ]'";
        ExecStart = "${mako.package}/bin/mako -c ${makoConfig}";
        ExecReload = "${mako.package}/bin/makoctl reload";
        Type = "dbus";
      };
      wantedBy = [ "graphical-session.target" ];
    };
    thoughtfull.programs.fuzzel.enable = mkDefault mako.enable;
  };
  options.thoughtfull.programs.mako = {
    enable = mkEnableOption "mako";
    package = mkOption {
      default = pkgs.mako;
      type = types.package;
    };
  };
}
