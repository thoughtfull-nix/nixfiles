{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault mkIf mkOption;
  inherit (lib.thoughtfull.types) selectorFunction;
  inherit (lib.types) lines;
  inherit (pkgs)
    aspell
    aspellDicts
    bash
    emacs
    emacs-all-the-icons-fonts
    silver-searcher
    unzip
    ;
  inherit (pkgs.thoughtfull) writeFile writeFileScript;
  cfg = config.services.emacs;
  login = writeFileScript {
    name = "emacs-client-login";
    replacements = {
      bash = "${bash}/bin/bash";
      emacsclient = "${cfg.package}/bin/emacsclient";
      swaymsg = "${sway.package}/bin/swaymsg";
    };
    src = ./emacs/login.bash;
  };
in
{
  config = {
    environment.systemPackages = mkIf cfg.enable [
      aspell
      aspellDicts.en
      aspellDicts.en-computers
      aspellDicts.en-science
      silver-searcher
      # for loading files from JARs
      unzip
    ];
    fonts.packages = mkIf (cfg.enable && graphical.enable) [
      emacs-all-the-icons-fonts
      # source-code-pro
    ];
    services.emacs = {
      defaultEditor = mkDefault true;
      package =
        let
          default = writeFile {
            name = "default.el";
            directory = "/share/emacs/site-lisp";
            replacements = { inherit (cfg.thoughtfull) extraConfig; };
            src = ./emacs/default.el;
          };
        in
        mkDefault (
          emacs.pkgs.emacsWithPackages (
            epkgs:
            [
              default
              epkgs.thoughtfull
            ]
            ++ (cfg.thoughtfull.extraPackages epkgs)
          )
        );
      startWithGraphical = mkDefault graphical.enable;
    };
    thoughtfull.impermanence.user.directories = mkIf cfg.enable [ ".config/emacs" ];
    systemd.user.services.emacs-client-login = {
      description = "Open an emacs frame on workspace 2 at login";
      # Ordered after emacs.service itself (not just sway-session.target) so
      # this doesn't even attempt emacsclient before the daemon exists; see
      # emacs/login.bash for why that also means no retry is needed here.
      after = [
        "sway-session.target"
        "emacs.service"
        "waybar.service"
      ];
      wants = [ "emacs.service" ];
      # See gtk-defaults in sway.nix for why partOf (follow sway-session
      # down) rather than bindsTo (would also pull sway-session.target up on
      # a lone `systemctl --user start emacs-client-login.service`, which
      # isn't wanted here). Deliberately not partOf emacs.service: the
      # daemon's own lifecycle (e.g. surviving a crash-restart) is
      # independent of this one-off login trigger.
      partOf = [ "sway-session.target" ];
      enable = mkDefault (sway.enable && cfg.enable);
      wantedBy = [ "sway-session.target" ];
      # A rebuild-switch that touches this unit's closure (e.g. an
      # emacs/sway package bump) shouldn't reopen a frame mid-session.
      # (No KillMode=process here unlike foot/firefox/slack-login: this
      # script doesn't background anything, it just tells the daemon to
      # create a frame and exits, so nothing of the frame lives in this
      # unit's control group to begin with.)
      restartIfChanged = mkDefault false;
      serviceConfig = {
        Type = "oneshot";
        # See foot-login in foot.nix for why oneshot + RemainAfterExit here.
        RemainAfterExit = true;
        ExecStart = "${login}";
      };
    };
  };
  options.services.emacs.thoughtfull = {
    extraConfig = mkOption {
      default = "";
      description = "Extra elisp configuration appended to default.el";
      type = lines;
    };
    extraPackages = mkOption {
      default = _self: [ ];
      description = "Extra packages added to Emacs";
      type = selectorFunction;
    };
  };
}
