{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) zsh;
  inherit (lib) mkDefault mkIf;
in
{
  environment.systemPackages = mkIf zsh.enable [ pkgs.tldr ];
  programs.zsh = {
    autosuggestions.enable = mkDefault true;
    histFile = "$HOME/.config/zsh/history";
    histSize = mkDefault 10000;
    # zshrc
    interactiveShellInit = ''
      # run-help is aliased to man which shadows the help files. for built-ins, emulate bash help by
      # redefining run-help
      # https://stackoverflow.com/a/7060716
      unalias run-help
      autoload run-help
      # Inspired by https://superuser.com/a/1930960
      help() {
        { ${pkgs.tldr}/bin/tldr "$@" || man "$@" || "$@" --help || run-help "$@" } 2>/dev/null
      }
    '';
    # zprofile
    loginShellInit = "";
    # zshrc
    promptInit = "";
    setOptions = [
      # if command cannot be found and is a directory name, then cd into it
      "AUTO_CD"
      # corrections based on Dvorak keyboard
      "DVORAK"
      # skip duplicates when searching history
      "HIST_FIND_NO_DUPS"
      # do not store duplicate of previous command
      "HIST_IGNORE_DUPS"
      # make history available immediately across shell instances
      "SHARE_HISTORY"
    ];
    # zshrc
    shellAliases = {
      color-picker = "hyprpicker";
      # rerun last command piped to less
      l = "fc -e- | less";
    };
    # zshenv
    shellInit = ''
      export ZDOTDIR=$HOME/.config/zsh

      # this seems the simplest way to disable the newuser wizard
      # https://unix.stackexchange.com/a/57926
      zsh-newuser-install() { :; }
    '';
    syntaxHighlighting = {
      enable = mkDefault true;
      highlighters = [
        "main"
        "root"
      ];
    };
  };
  thoughtfull.impermanence.user.directories = mkIf zsh.enable [ ".config/zsh" ];
  users.defaultUserShell = mkIf zsh.enable pkgs.zsh;
}
