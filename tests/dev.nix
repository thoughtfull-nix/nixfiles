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

    with subtest("disabled default: devenv is not available"):
        disabled.fail("which devenv")
  '';
}
