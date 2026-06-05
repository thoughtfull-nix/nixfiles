{ nixpkgs, ... }:
let
  # Stub the thoughtfull sub-module options that dev.nix sets via mkDefault
  thoughtfullSubModuleStub =
    { lib, ... }:
    {
      options.thoughtfull = {
        claude.enable = lib.mkEnableOption "claude (stub)";
        clojure.enable = lib.mkEnableOption "clojure (stub)";
        rust.enable = lib.mkEnableOption "rust (stub)";
      };
    };
in
nixpkgs.testers.nixosTest {
  name = "dev";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    enabled = {
      imports = [
        ../nixosModules/dev.nix
        thoughtfullSubModuleStub
      ];
      thoughtfull.dev.enable = true;
      # nixosModules/java.nix sets programs.java.enable = mkDefault true in the
      # full system; mirror that here so the package selection is exercised.
      programs.java.enable = true;
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
    disabled.wait_for_unit("multi-user.target")

    with subtest("enabled: devenv is in PATH"):
        enabled.succeed("which devenv")

    with subtest("enabled: git is in PATH"):
        enabled.succeed("which git")

    with subtest("enabled: java is in PATH and is JDK 25"):
        result = enabled.succeed("java -version 2>&1")
        print(f"java -version: {result}")
        assert "25" in result, f"expected JDK 25 (temurin-bin.jdk-25), got: {result}"

    with subtest("disabled default: devenv is not available"):
        disabled.fail("which devenv")
  '';
}
