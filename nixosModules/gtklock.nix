{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) gnupg;
  inherit (lib) mkDefault;
  inherit (pkgs)
    bash
    gtklock
    mako
    util-linux
    ;
  inherit (pkgs.thoughtfull) theme-toggle writeFileScriptBin;
  clear-secrets = writeFileScriptBin {
    name = "clear-secrets";
    replacements = {
      bash = "${bash}/bin/bash";
      gpgconf = "${gnupg.package}/bin/gpgconf";
    };
    src = ./gtklock/clear-secrets.bash;
  };
  gtklock-wrapper = writeFileScriptBin {
    name = "gtklock";
    replacements = {
      bash = "${bash}/bin/bash";
      flock = "${util-linux}/bin/flock";
      gtklock = "${gtklock}/bin/gtklock";
      makoctl = "${mako}/bin/makoctl";
      theme-get = "${theme-toggle}/bin/theme-get";
    };
    src = ./gtklock/wrapper.bash;
  };
in
{
  environment.systemPackages = [ clear-secrets ];
  programs.gtklock = {
    package = mkDefault gtklock-wrapper;
    config.main = {
      idle-hide = mkDefault true;
      idle-timeout = mkDefault 60;
      lock-command = mkDefault "${clear-secrets}/bin/clear-secrets";
      start-hidden = mkDefault true;
    };
    modules = with pkgs; [
      gtklock-powerbar-module
      gtklock-userinfo-module
    ];
  };
}
