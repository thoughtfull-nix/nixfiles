{ nixpkgs, ... }:
let
  # Stub the agenix `age.secrets` option so we can test the module's
  # `nix.extraOptions` synthesis without actually pulling in the agenix
  # activation scripts (which need a real SSH identity to decrypt).
  ageSecretsStub =
    { lib, ... }:
    {
      options.age.secrets = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                file = lib.mkOption { type = lib.types.path; };
                path = lib.mkOption {
                  type = lib.types.str;
                  default = "/run/agenix/${name}";
                };
              };
            }
          )
        );
      };
    };
in
nixpkgs.testers.nixosTest {
  name = "github-token";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    withToken =
      { pkgs, ... }:
      {
        imports = [
          ../nixosModules/github-token.nix
          ageSecretsStub
        ];
        # Use a fake plaintext file instead of the real .age fixture so the
        # test doesn't depend on the encrypted secret being decryptable.
        thoughtfull.githubToken.tokenFile = pkgs.writeText "fake-token" "fake";
      };

    withoutToken = {
      imports = [
        ../nixosModules/github-token.nix
        ageSecretsStub
      ];
      thoughtfull.githubToken.tokenFile = null;
    };
  };

  testScript = ''
    start_all()
    withToken.wait_for_unit("multi-user.target")
    withoutToken.wait_for_unit("multi-user.target")

    with subtest("default: tokenFile set => nix.conf !includes the agenix path"):
        nix_conf = withToken.succeed("cat /etc/nix/nix.conf")
        print(f"withToken nix.conf:\n{nix_conf}")
        assert "!include /run/agenix/github-access-token" in nix_conf, (
            "nix.conf should !include the decrypted token file"
        )

    with subtest("tokenFile null: nix.conf has no !include line"):
        nix_conf = withoutToken.succeed("cat /etc/nix/nix.conf")
        print(f"withoutToken nix.conf:\n{nix_conf}")
        assert "!include" not in nix_conf, (
            "nix.conf should not contain !include when tokenFile is null"
        )
        assert "agenix" not in nix_conf, (
            "nix.conf should not reference agenix paths when tokenFile is null"
        )
  '';
}
