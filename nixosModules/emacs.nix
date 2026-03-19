{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault mkIf mkOption;
  inherit (lib.thoughtfull.types) selectorFunction;
  inherit (lib.types) lines;
  inherit (pkgs)
    aspell
    aspellDicts
    emacs
    emacs-all-the-icons-fonts
    silver-searcher
    unzip
    ;
  inherit (pkgs.thoughtfull) writeFile;
  cfg = config.services.emacs;
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
