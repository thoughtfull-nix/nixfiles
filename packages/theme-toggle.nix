{ lib, pkgs, ... }:
let
  inherit (pkgs)
    bash
    glib
    jq
    moreutils
    procps
    sway
    symlinkJoin
    ;
  inherit (lib) writeFileScriptBin;
  theme-get = writeFileScriptBin {
    name = "theme-get";
    replacements = {
      bash = "${bash}/bin/bash";
    };
    src = ./theme-toggle/theme-get.bash;
  };
  theme-toggle = writeFileScriptBin {
    name = "theme-toggle";
    replacements = {
      bash = "${bash}/bin/bash";
      gsettings = "${glib}/bin/gsettings";
      jq = "${jq}/bin/jq";
      pkill = "${procps}/bin/pkill";
      sponge = "${moreutils}/bin/sponge";
      theme-get = "${theme-get}/bin/theme-get";
      theme-sway = "${theme-sway}/bin/theme-sway";
    };
    src = ./theme-toggle/theme-toggle.bash;
  };
  theme-sway = writeFileScriptBin {
    name = "theme-sway";
    replacements = {
      bash = "${bash}/bin/bash";
      swaymsg = "${sway}/bin/swaymsg";
      theme-get = "${theme-get}/bin/theme-get";
    };
    src = ./theme-toggle/theme-sway.bash;
  };
  theme-toggle-status = writeFileScriptBin {
    name = "theme-toggle-status";
    replacements = {
      bash = "${bash}/bin/bash";
      theme-get = "${theme-get}/bin/theme-get";
    };
    src = ./theme-toggle/theme-toggle-status.bash;
  };
in
symlinkJoin {
  name = "theme";
  paths = [
    theme-get
    theme-toggle
    theme-toggle-status
    theme-sway
  ];
}
