{ self, nixpkgs, ... }:
let
  stubs = import ./stubs.nix;
  genericHello = import ./generic-hello.nix nixpkgs;

  # dev.nix pulls llm-agents packages from pkgs; module-set nixpkgs.overlays is
  # ignored with external pkgs, so apply the overlay here (see tests/default.nix).
  extendedNixpkgs = nixpkgs.extend self.inputs.llm-agents.overlays.shared-nixpkgs;

  # dev.nix takes codex from inputs.llm-agents.packages (built against
  # llm-agents' pinned nixpkgs, so cached by numtide) rather than the
  # shared-nixpkgs overlay, so the module needs `inputs` in scope.
  inputsArg = {
    _module.args.inputs = self.inputs // {
      inherit self;
    };
  };

  opencodeDirectories = [
    ".cache/opencode"
    ".config/opencode"
    ".local/share/opencode"
    ".local/state/opencode"
  ];

  # The Maven local repository is persisted across boots so downloaded
  # artifacts survive a reboot, but excluded from restic (backup = false):
  # it is a disposable, re-downloadable cache.
  mavenRepository = {
    directory = ".m2/repository";
    backup = false;
  };
  hasMavenRepository =
    config:
    builtins.any (
      d: (d.directory or null) == mavenRepository.directory && (d.backup or true) == false
    ) config.thoughtfull.impermanence.user.directories;

  # Editor installs (Unity/Hub), project caches, and Asset Store downloads are
  # persisted but excluded from restic; projects, Hub state, and licences are
  # backed up.
  unityDirectories = [
    {
      directory = "Unity";
      backupExclude = [
        "Hub"
        "**/Library"
        "**/Logs"
        "**/Temp"
      ];
    }
    {
      directory = ".config/unityhub";
      backupExclude = [
        "Cache"
        "Code Cache"
        "Crashpad"
        "DawnGraphiteCache"
        "DawnWebGPUCache"
        "GPUCache"
      ];
    }
    {
      directory = ".config/unity3d";
      backupExclude = [ ];
    }
    {
      directory = ".local/share/unity3d";
      backupExclude = [ "Asset Store-5.x" ];
    }
  ];
  # Codex caches and scratch space are excluded from restic.
  codexDirectory = {
    directory = ".codex";
    backupExclude = [
      ".tmp"
      "cache"
      "plugins/cache"
      "tmp"
    ];
  };
  hasPersistedDirectory =
    config: expected:
    builtins.any (
      entry:
      let
        d = if builtins.isString entry then { directory = entry; } else entry;
      in
      d.directory == expected.directory
      && (d.backup or true)
      && (d.backupExclude or [ ]) == expected.backupExclude
    ) config.thoughtfull.impermanence.user.directories;
  persistsAnyUnityDirectory =
    config:
    builtins.any (
      d: builtins.elem (d.directory or d) (map (u: u.directory) unityDirectories)
    ) config.thoughtfull.impermanence.user.directories;

  # Stub the thoughtfull sub-module options that dev.nix sets via mkDefault
  # (clojure and rust; impermanence.user is covered by stubs.impermanence).
  thoughtfullSubModuleStub =
    { lib, ... }:
    {
      options.thoughtfull = {
        clojure.enable = lib.mkEnableOption "clojure (stub)";
        rust.enable = lib.mkEnableOption "rust (stub)";
      };
    };
in
extendedNixpkgs.testers.nixosTest {
  name = "dev";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    enabled =
      { config, ... }:
      {
        imports = [
          ../nixosModules/dev.nix
          thoughtfullSubModuleStub
          stubs.impermanence
          inputsArg
        ];
        thoughtfull.dev.enable = true;
        # nixosModules/java.nix sets programs.java.enable = mkDefault true in the
        # full system; mirror that here so the package selection is exercised.
        programs.java.enable = true;
        # zsh is this repo's default shell; enable it so the zsh auto-activation
        # hook is exercised.
        programs.zsh.enable = true;
        assertions =
          map (directory: {
            assertion = builtins.elem directory config.thoughtfull.impermanence.user.directories;
            message = "expected opencode persistence directory ${directory}";
          }) opencodeDirectories
          ++ [
            {
              assertion = hasMavenRepository config;
              message = "expected Maven repository persisted with backup = false by default";
            }
            {
              assertion = !(persistsAnyUnityDirectory config);
              message = "unexpected Unity persistence by default";
            }
            {
              assertion = hasPersistedDirectory config codexDirectory;
              message = "expected .codex persisted with caches excluded from backups";
            }
          ];
      };

    javaDisabled =
      { config, ... }:
      {
        imports = [
          ../nixosModules/dev.nix
          thoughtfullSubModuleStub
          stubs.impermanence
          inputsArg
        ];
        thoughtfull.dev = {
          enable = true;
          java.enable = false;
        };
        assertions = [
          {
            assertion = !(hasMavenRepository config);
            message = "unexpected Maven repository persistence when java disabled";
          }
        ];
      };

    opencodeDisabled =
      { config, ... }:
      {
        imports = [
          ../nixosModules/dev.nix
          thoughtfullSubModuleStub
          stubs.impermanence
          inputsArg
        ];
        thoughtfull.dev = {
          enable = true;
          agents.opencode.enable = false;
        };
        programs.java.enable = true;
        assertions = map (directory: {
          assertion = !(builtins.elem directory config.thoughtfull.impermanence.user.directories);
          message = "unexpected opencode persistence directory ${directory}";
        }) opencodeDirectories;
      };

    unityEnabled =
      { config, ... }:
      {
        imports = [
          ../nixosModules/dev.nix
          thoughtfullSubModuleStub
          stubs.impermanence
          inputsArg
        ];
        thoughtfull.dev = {
          enable = true;
          unity.enable = true;
        };
        assertions = map (expected: {
          assertion = hasPersistedDirectory config expected;
          message = "expected Unity persistence directory ${expected.directory} with backupExclude ${builtins.toJSON expected.backupExclude}";
        }) unityDirectories;
      };

    disabled = {
      imports = [
        ../nixosModules/dev.nix
        thoughtfullSubModuleStub
        stubs.impermanence
        inputsArg
      ];
      # Enable zsh so /etc/zshrc exists to assert the hook is absent.
      programs.zsh.enable = true;
    };
  };

  testScript = ''
    import json

    start_all()
    enabled.wait_for_unit("multi-user.target")
    opencodeDisabled.wait_for_unit("multi-user.target")
    javaDisabled.wait_for_unit("multi-user.target")
    unityEnabled.wait_for_unit("multi-user.target")
    disabled.wait_for_unit("multi-user.target")

    with subtest("enabled: devenv is in PATH"):
        enabled.succeed("which devenv")

    with subtest("enabled: zsh devenv auto-activation hook is configured"):
        enabled.succeed("grep -q 'devenv hook zsh' /etc/zshrc")

    with subtest("enabled: java is in PATH and is JDK 25"):
        result = enabled.succeed("java -version 2>&1")
        print(f"java -version: {result}")
        assert "25" in result, f"expected JDK 25 (temurin-bin.jdk-25), got: {result}"

    with subtest("enabled default: claude is in PATH"):
        enabled.succeed("which claude")

    with subtest("enabled default: Claude Code runs git and ssh outside its sandbox"):
        settings = json.loads(enabled.succeed("cat /etc/claude-code/managed-settings.json"))
        excluded = settings["sandbox"]["excludedCommands"]
        assert "git *" in excluded and "ssh *" in excluded, excluded

    with subtest("enabled default: generic Linux binaries run"):
        enabled.succeed("${genericHello}/bin/hello")

    with subtest("enabled default: codex is in PATH"):
        enabled.succeed("which codex")

    with subtest("enabled default: opencode is in PATH"):
        enabled.succeed("which opencode")

    with subtest("enabled default: unityhub is not available"):
        enabled.fail("which unityhub")

    with subtest("unity enabled: unityhub is in PATH"):
        unityEnabled.succeed("which unityhub")

    with subtest("opencode disabled: opencode is not available"):
        opencodeDisabled.fail("which opencode")

    with subtest("disabled default: devenv is not available"):
        disabled.fail("which devenv")

    with subtest("disabled default: claude is not available"):
        disabled.fail("which claude")

    with subtest("disabled default: no Claude Code managed settings"):
        disabled.fail("test -e /etc/claude-code/managed-settings.json")

    with subtest("disabled default: generic Linux binaries do not run"):
        disabled.fail("${genericHello}/bin/hello")

    with subtest("disabled default: codex is not available"):
        disabled.fail("which codex")

    with subtest("disabled default: opencode is not available"):
        disabled.fail("which opencode")

    with subtest("disabled default: unityhub is not available"):
        disabled.fail("which unityhub")

    with subtest("disabled default: no devenv auto-activation hook"):
        disabled.fail("grep -q 'devenv hook' /etc/zshrc")
  '';
}
