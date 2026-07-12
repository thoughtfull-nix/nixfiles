{ self, nixpkgs, ... }:
let
  # dev.nix pulls llm-agents packages from pkgs; module-set nixpkgs.overlays is
  # ignored with external pkgs, so apply the overlay here (see tests/default.nix).
  extendedNixpkgs = nixpkgs.extend self.inputs.llm-agents.overlays.default;

  opencodeDirectories = [
    ".cache/opencode"
    ".config/opencode"
    ".local/share/opencode"
    ".local/state/opencode"
  ];

  # Stub the thoughtfull sub-module options that dev.nix sets via mkDefault
  thoughtfullSubModuleStub =
    { lib, ... }:
    {
      options.thoughtfull = {
        clojure.enable = lib.mkEnableOption "clojure (stub)";
        rust.enable = lib.mkEnableOption "rust (stub)";
        impermanence.user = {
          files = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          directories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
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
        ];
        thoughtfull.dev.enable = true;
        # nixosModules/java.nix sets programs.java.enable = mkDefault true in the
        # full system; mirror that here so the package selection is exercised.
        programs.java.enable = true;
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
      ];
    };
  };

  testScript = ''
    start_all()
    enabled.wait_for_unit("multi-user.target")
    opencodeDisabled.wait_for_unit("multi-user.target")
    disabled.wait_for_unit("multi-user.target")

    with subtest("enabled: devenv is in PATH"):
        enabled.succeed("which devenv")

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
  '';
}
