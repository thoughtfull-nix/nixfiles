{
  config,
  inputs,
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
    mkMerge
    optionals
    ;
  inherit (pkgs) sox;
in
{
  config = mkMerge [
    (mkIf ((dev.enable && claude.enable) || config.thoughtfull.claudeDesktop.enable or false) {
      # Claude Code's sandbox runs commands in a user namespace where root-owned
      # files appear owned by nobody, which ssh rejects in its config includes
      environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
        sandbox.excludedCommands = [
          "git *"
          "ssh *"
        ];
      };
    })
    (mkIf dev.enable {
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
        # codex is built from source (Rust), so the shared-nixpkgs overlay would
        # rebuild it against our nixpkgs and miss numtide's cache. Take it from
        # llm-agents' own output, which is built against its pinned nixpkgs and
        # cached by numtide's CI.
        ++ (optionals codex.enable [
          inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
        ])
        ++ (optionals opencode.enable [ llm-agents.opencode ]);
      # dev tools, agents, plugins, and MCP servers download generic Linux binaries
      programs.nix-ld.enable = mkDefault true;
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
        ++ (optionals codex.enable [
          {
            directory = ".codex";
            backupExclude = [
              ".tmp"
              "cache"
              "plugins/cache"
              "tmp"
            ];
          }
        ])
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
    })
  ];
  imports = [
    ./dev/android.nix
    ./dev/java.nix
    ./dev/unity.nix
  ];
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
