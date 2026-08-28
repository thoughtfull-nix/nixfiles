{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) dev;
  inherit (dev.agents) claude codex opencode;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    optionals
    ;
  inherit (pkgs) sox;
in
{
  config = mkIf dev.enable {
    environment.systemPackages =
      with pkgs;
      [
        devenv
        gh
      ]
      ++ (optionals claude.enable [
        llm-agents.claude-code
        sox
      ])
      ++ (optionals codex.enable [
        llm-agents.codex
      ])
      ++ (optionals opencode.enable [ llm-agents.opencode ]);
    thoughtfull = {
      clojure.enable = mkDefault true;
      rust.enable = mkDefault true;
    };
    thoughtfull.impermanence.user = {
      directories = [
        ".config/gh"
        ".local/share/devenv"
      ]
      ++ (optionals claude.enable [ ".claude" ])
      ++ (optionals codex.enable [ ".codex" ])
      ++ (optionals opencode.enable [
        ".cache/opencode"
        ".config/opencode"
        ".local/share/opencode"
        ".local/state/opencode"
      ]);
      files = optionals claude.enable [ ".claude.json" ];
    };
    # Auto-activate the devenv environment on directory change.
    # https://devenv.sh/auto-activation/
    programs.zsh.interactiveShellInit = mkIf config.programs.zsh.enable ''
      eval "$(devenv hook zsh)"
    '';
  };
  imports = [ ./dev/java.nix ];
  options.thoughtfull.dev = {
    agents = {
      claude.enable = (mkEnableOption "Claude code agent") // {
        default = true;
      };
      codex.enable = (mkEnableOption "Codex code agent") // {
        default = true;
      };
      opencode.enable = (mkEnableOption "OpenCode agent") // {
        default = true;
      };
    };
    enable = mkEnableOption "development configuration";
  };
}
