{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault;
  inherit (pkgs) bash foot;
  inherit (pkgs.thoughtfull) theme-toggle writeFileScriptBin;
  footWrapper = writeFileScriptBin {
    name = "foot";
    replacements = {
      bash = "${bash}/bin/bash";
      foot = "${foot}/bin/foot";
      theme-get = "${theme-toggle}/bin/theme-get";
    };
    src = ./foot/wrapper.bash;
  };
in
{
  programs.foot = {
    enable = mkDefault graphical.enable;
    package = mkDefault footWrapper;
    settings = {
      main.font = mkDefault "FiraCode Nerd Font:size=11";
      # Adwaita light theme (applied via SIGUSR1 signal for runtime switching)
      colors-dark = {
        background = mkDefault "ffffff";
        foreground = mkDefault "1e1e1e";
        regular0 = mkDefault "1e1e1e";
        regular1 = mkDefault "c01c28";
        regular2 = mkDefault "26a269";
        regular3 = mkDefault "a2734c";
        regular4 = mkDefault "12488b";
        regular5 = mkDefault "a347ba";
        regular6 = mkDefault "2aa1b3";
        regular7 = mkDefault "d0cfcc";
        bright0 = mkDefault "5e5c64";
        bright1 = mkDefault "f66151";
        bright2 = mkDefault "33d17a";
        bright3 = mkDefault "e9ad0c";
        bright4 = mkDefault "2a7bde";
        bright5 = mkDefault "c061cb";
        bright6 = mkDefault "33c7de";
        bright7 = mkDefault "ffffff";
      };
      # Adwaita dark theme (applied via SIGUSR2 signal for runtime switching)
      colors-light = {
        background = mkDefault "1e1e1e";
        foreground = mkDefault "ffffff";
        regular0 = mkDefault "1e1e1e";
        regular1 = mkDefault "c01c28";
        regular2 = mkDefault "26a269";
        regular3 = mkDefault "a2734c";
        regular4 = mkDefault "12488b";
        regular5 = mkDefault "a347ba";
        regular6 = mkDefault "2aa1b3";
        regular7 = mkDefault "d0cfcc";
        bright0 = mkDefault "5e5c64";
        bright1 = mkDefault "f66151";
        bright2 = mkDefault "33d17a";
        bright3 = mkDefault "e9ad0c";
        bright4 = mkDefault "2a7bde";
        bright5 = mkDefault "c061cb";
        bright6 = mkDefault "33c7de";
        bright7 = mkDefault "ffffff";
      };
    };
  };
}
