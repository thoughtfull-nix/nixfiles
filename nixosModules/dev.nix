{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) dev;
  inherit (dev.agents) claude opencode;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    optionals
    ;
in
{
  config = mkIf dev.enable {
    environment.systemPackages =
      with pkgs;
      [
        devenv
        gh
      ]
      ++ (optionals claude.enable [ llm-agents.claude-code ])
      ++ (optionals opencode.enable [ llm-agents.opencode ]);
    programs.java.package = mkDefault pkgs.javaPackages.compiler.temurin-bin.jdk-25;
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
  options.thoughtfull.dev = {
    agents = {
      claude.enable = (mkEnableOption "Claude code agent") // {
        default = true;
      };
      opencode.enable = (mkEnableOption "OpenCode agent") // {
        default = true;
      };
    };
    enable = mkEnableOption "development configuration";
  };
}
