# Lightweight nix eval check (not a nixosTest/VM boot) for github-token.nix:
# verifying nix.extraOptions !includes the decrypted token path when tokenFile
# is set, and carries no !include/agenix reference when it's null.
#
# A VM boot was considered and rejected: the module only ever contributes a
# static string to nix.extraOptions -- nothing about the nix daemon actually
# reading that !include at runtime is under test, so `config.nix.extraOptions`
# is exactly what a real /etc/nix/nix.conf would render, without needing to
# boot anything to read it back.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        ../nixosModules/github-token.nix
        stubs.ageSecrets
        extraModule
      ];
    };

  withToken = mkEval (
    { pkgs, ... }:
    {
      thoughtfull.githubToken.tokenFile = pkgs.writeText "fake-token" "fake";
    }
  );
  withoutToken = mkEval { thoughtfull.githubToken.tokenFile = null; };

  checks = [
    {
      name = "default: tokenFile set => nix.conf !includes the agenix path";
      ok = lib.hasInfix "!include /run/agenix/github-access-token" withToken.config.nix.extraOptions;
    }
    {
      name = "tokenFile null: nix.conf has no !include line";
      ok = !(lib.hasInfix "!include" withoutToken.config.nix.extraOptions);
    }
    {
      name = "tokenFile null: nix.conf has no agenix reference";
      ok = !(lib.hasInfix "agenix" withoutToken.config.nix.extraOptions);
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    github-token test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "github-token-test" { } "touch $out"
