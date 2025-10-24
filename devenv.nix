{
  config,
  lib,
  ...
}:
{
  difftastic.enable = true;
  git-hooks.hooks = {
    check-added-large-files.enable = true;
    check-case-conflicts.enable = true;
    check-executables-have-shebangs.enable = true;
    check-merge-conflicts.enable = true;
    check-shebang-scripts-are-executable.enable = true;
    check-symlinks.enable = true;
    deadnix = {
      enable = true;
      excludes = [
        "nixosConfigurations/[^/]*/hardware-configuration.nix"
      ];
      settings = {
        edit = true;
        noUnderscore = true;
      };
    };
    detect-aws-credentials.enable = true;
    detect-private-keys.enable = true;
    eclint = {
      enable = true;
      settings.fix = true;
    };
    end-of-file-fixer.enable = true;
    flake-checker = {
      enable = true;
      args = lib.cli.toGNUCommandLine { } {
        check-outdated = true;
        check-supported = true;
        no-telemetry = true;
      };
    };
    gitlint = {
      args =
        (lib.cli.toGNUCommandLine { } {
          C = ".config/gitlint.ini";
          staged = true;
        })
        ++ [ "--msg-filename" ];
      enable = true;
      entry = "${config.git-hooks.hooks.gitlint.package}/bin/gitlint";
    };
    mixed-line-endings.enable = true;
    nixfmt-rfc-style = {
      enable = true;
      excludes = [
        "nixosConfigurations/[^/]*/hardware-configuration.nix"
      ];
      settings.width = 100;
    };
    ripsecrets.enable = true;
    shellcheck = {
      args = lib.cli.toGNUCommandLine { } {
        e = [
          # using replaceVars with bash makes these unhappy
          "SC1008" # This shebang was unrecognized.
          "SC2239" # Ensure the shebang uses an absolute path to the interpreter.

          # argc tends to trip this, and I use 'set -u' anyway
          "SC2154" # Var is referenced but not assigned.
        ];
      };
      enable = true;
    };
    shfmt = {
      args = lib.cli.toGNUCommandLine { } {
        i = 2;
        ci = true;
      };
      enable = true;
    };
    sort-file-contents = {
      enable = true;
      files = "(\.config/vale/config/ignore/.*)|\.gitignore";
    };
    statix = {
      enable = true;
      settings.config = ".config/statix.toml";
    };
    trim-trailing-whitespace.enable = true;
    typos = {
      enable = true;
      excludes = [
        "\.config/.*"
      ];
      files = ".(md|org|txt)$";
      settings.configPath = ".config/typos.toml";
    };
    vale = {
      enable = true;
      excludes = [
        "\.config/.*"
        "LICENSE.txt"
      ];
      files = ".(md|org|txt)$";
      settings.configPath = ".config/vale.ini";
    };
    yamlfmt = {
      enable = true;
      excludes = [
        ".config/vale/Google/.*"
      ];
      settings = {
        configPath = ".config/yamlfmt.yaml";
        lint-only = false;
      };
    };
    yamllint = {
      enable = true;
      excludes = [
        ".config/vale/Google/.*"
      ];
      settings.configPath = ".config/yamllint.yaml";
    };
  };
  languages.nix.enable = true;
}
