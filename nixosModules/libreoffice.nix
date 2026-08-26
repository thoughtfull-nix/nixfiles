{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  inherit (pkgs) libreoffice hunspellDicts hyphenDicts;
  cfg = config.thoughtfull.programs.libreoffice;
in
{
  config = mkIf cfg.enable {
    # LibreOffice ships no dictionaries; its wrapper auto-adds any
    # share/hunspell and share/hyphen from NIX_PROFILES to DICPATH, so the
    # dictionary packages just need to be on the system profile.
    environment.systemPackages = [
      libreoffice
      hunspellDicts.en_US
      hyphenDicts.en_US
    ];
    thoughtfull.impermanence.user.directories = [ ".config/libreoffice" ];
  };
  options.thoughtfull.programs.libreoffice.enable = mkEnableOption "libreoffice";
}
