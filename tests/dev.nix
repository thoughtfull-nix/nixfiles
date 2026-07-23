{ self, nixpkgs, ... }:
let
  stubs = import ./stubs.nix;

  # dev.nix pulls llm-agents packages from pkgs; module-set nixpkgs.overlays is
  # ignored with external pkgs, so apply the overlay here (see tests/default.nix).
  extendedNixpkgs = nixpkgs.extend self.inputs.llm-agents.overlays.shared-nixpkgs;

  opencodeDirectories = [
    ".cache/opencode"
    ".config/opencode"
    ".local/share/opencode"
    ".local/state/opencode"
  ];

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
        ];
        thoughtfull.dev.enable = true;
        # nixosModules/java.nix sets programs.java.enable = mkDefault true in the
        # full system; mirror that here so the package selection is exercised.
        programs.java.enable = true;
        # zsh is this repo's default shell; enable it so the zsh auto-activation
        # hook is exercised.
        programs.zsh.enable = true;
        assertions = map (directory: {
          assertion = builtins.elem directory config.thoughtfull.impermanence.user.directories;
          message = "expected opencode persistence directory ${directory}";
        }) opencodeDirectories;
      };

    opencodeDisabled =
      { config, ... }:
      {
        imports = [
          ../nixosModules/dev.nix
          thoughtfullSubModuleStub
          stubs.impermanence
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

    disabled = {
      imports = [
        ../nixosModules/dev.nix
        thoughtfullSubModuleStub
        stubs.impermanence
      ];
      # Enable zsh so /etc/zshrc exists to assert the hook is absent.
      programs.zsh.enable = true;
    };
  };

  testScript = ''
    start_all()
    enabled.wait_for_unit("multi-user.target")
    opencodeDisabled.wait_for_unit("multi-user.target")
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

    with subtest("enabled default: opencode is in PATH"):
        enabled.succeed("which opencode")

    with subtest("opencode disabled: opencode is not available"):
        opencodeDisabled.fail("which opencode")

    with subtest("disabled default: devenv is not available"):
        disabled.fail("which devenv")

    with subtest("disabled default: claude is not available"):
        disabled.fail("which claude")

    with subtest("disabled default: opencode is not available"):
        disabled.fail("which opencode")

    with subtest("disabled default: no devenv auto-activation hook"):
        disabled.fail("grep -q 'devenv hook' /etc/zshrc")
  '';
}
