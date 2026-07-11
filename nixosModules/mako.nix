{
  config,
  lib,
  pkgs,
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
  inherit (pkgs.thoughtfull) writeFileScriptBin;
  makoDismiss = writeFileScriptBin {
    name = "mako-dismiss";
    src = ./mako/dismiss.bash;
  };
  makoToggleDnd = writeFileScriptBin {
    name = "mako-toggle-dnd";
    src = ./mako/toggle-dnd.bash;
  };
  # `builtins.path` forces an independent, content-addressed copy of just this file into the
  # store -- without it, this path literal instead resolves to a subpath of the flake's own
  # whole-source checkout, which is never registered as a declared input anywhere it gets
  # substituted in as text, so `makoConfig`'s embedded path ends up pointing at a path absent from
  # `mako.package`'s actual runtime closure on any machine that doesn't separately already have
  # this flake's source in its store.
  makoConfig = replaceVars ./mako/config {
    notify = builtins.path {
      path = ./mako/notify.ogg;
      name = "notify.ogg";
    };
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
