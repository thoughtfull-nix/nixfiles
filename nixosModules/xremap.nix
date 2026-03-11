# taken (with changes) from https://github.com/xremap/nix-flake/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services) xremap;
  inherit (lib)
    getExe
    flatten
    lists
    mkDefault
    mkEnableOption
    mkMerge
    mkOption
    mkIf
    optional
    optionalAttrs
    types
    ;
  settingsFormat = pkgs.formats.yaml { };
  configFile = settingsFormat.generate "config.yml" xremap.config;
  startScript = builtins.concatStringsSep " " (
    flatten (
      lists.singleton "${getExe xremap.package}"
      ++ (if xremap.deviceNames != null then map (x: "--device '${x}'") xremap.deviceNames else [ ])
      ++ optional xremap.watch "--watch"
      ++ optional xremap.mouse "--mouse"
      ++ xremap.extraArgs
      ++ lists.singleton configFile
    )
  );
in
{
  config = mkIf xremap.enable {
    environment.systemPackages = [ xremap.package ];
    hardware.uinput.enable = mkDefault true;
    systemd.user.services.xremap = {
      after = [ "graphical-session.target" ];
      description = "xremap user service";
      path = [ xremap.package ];
      bindsTo = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = mkMerge [
        {
          KeyringMode = "private";
          SystemCallArchitectures = [ "native" ];
          RestrictRealtime = true;
          ProtectSystem = true;
          SystemCallFilter = map (x: "~@${x}") [
            "clock"
            "debug"
            "module"
            "reboot"
            "swap"
            "cpu-emulation"
            "obsolete"
            # NOTE: These two make the spawned processes drop cores
            # "privileged"
            # "resources"
          ];
          LockPersonality = true;
          UMask = "077";
          RestrictAddressFamilies = "AF_UNIX";
          ExecStart = startScript;
        }
        (optionalAttrs xremap.debug { Environment = [ "RUST_LOG=debug" ]; })
      ];
    };
    thoughtfull.user.extraGroups = mkIf xremap.enable [
      "input"
      "uinput"
    ];
  };
  options.services.xremap = {
    config = mkOption {
      default = import ./xremap/config.nix;
      description = "Xremap configuration. See xremap repo for examples.";
      example = ''
        {
          modmap = [
            {
              name = "Global",
              remap = {
                CapsLock = "Esc";
                Ctrl_L = "Esc";
              };
            }
          ];
          keymap = [
            {
              name = "Default (Nocturn, etc.)",
              application = {
              not = [ "Google-chrome", "Slack", "Gnome-terminal", "jetbrains-idea"];
              };
              remap = {
                # Emacs basic
                "C-b" = "left";
                "C-f" = "right";
              };
            }
          ];
        }
      '';
      type = types.submodule { freeformType = settingsFormat.type; };
    };
    debug = mkEnableOption "run xremap with RUST_LOG=debug in case upstream needs logs";
    deviceNames = mkOption {
      default = null;
      description = "List of devices to remap.";
      type = types.nullOr (types.listOf types.nonEmptyStr);
    };
    enable = mkEnableOption "xremap";
    extraArgs = mkOption {
      default = [ ];
      description = "Extra arguments for xremap";
      example = [ "--completions zsh" ];
      type = types.listOf types.str;
    };
    mouse = mkEnableOption "watching mice by default";
    package = mkOption {
      default = pkgs.xremap;
      type = types.package;
    };
    watch = mkEnableOption "running xremap watching new devices";
  };
}
