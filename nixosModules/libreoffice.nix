{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull.programs) libreoffice;
  inherit (lib) mkEnableOption mkIf;
in
{
  config = mkIf libreoffice.enable {
    # LibreOffice ships no dictionaries; its wrapper auto-adds any
    # share/hunspell and share/hyphen from NIX_PROFILES to DICPATH, so the
    # dictionary packages just need to be on the system profile.
    environment.systemPackages = [
      pkgs.libreoffice
      pkgs.hunspellDicts.en_US
      pkgs.hyphenDicts.en_US
    ];
    thoughtfull.impermanence.user.directories = [ ".config/libreoffice" ];
  };
  options.thoughtfull.programs.libreoffice.enable = mkEnableOption "libreoffice";
}
