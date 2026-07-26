# Lightweight nix eval check (not a nixosTest/VM boot) for the file-based key
# options in nixosModules/user.nix:
#   - sudoKeysFile: a plain path (public keys, not secret) rendered directly
#     as the source of the sudo authorized_keys.d entry.
#   - u2fKeyFiles: a list of age-encrypted files, one per pam_u2f credential.
#     Each gets its own age secret; an activation script decrypts, joins them
#     with ':', prefixes the username, and writes /etc/u2f-mappings.
#
# A VM boot was considered and rejected for the sudoKeysFile half of this --
# it's static wiring resolved at eval time (which file gets sourced), so
# reading config directly gives the same answer a booted VM would. The
# u2fKeyFiles activation script text is inspected as a string for the same
# reason: nothing here depends on a real age identity or an actual decrypt
# happening, just that the right paths and username land in the right places.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  defaultModule = import ../nixosModules/default.nix {
    inputs = self.inputs // {
      inherit self;
    };
  };

  baseModule =
    { lib, ... }:
    {
      # name must match the default keysHash so githubKeys hits the Nix store
      thoughtfull.user.name = "technosophist";
      # clear module-set nixpkgs.config to avoid the "external pkgs instance" assertion
      nixpkgs.config = lib.mkForce { };
      # openssh.nix disables automatic keygen; re-enable to mirror a real host
      systemd.services.sshd-keygen.enable = lib.mkForce true;
      # Disable services that need secrets or required options not suitable for eval
      services.syncthing.enable = lib.mkForce false;
      services.restic.thoughtfull.enable = lib.mkForce false;
      thoughtfull = {
        impermanence.enable = lib.mkForce false;
        monitoring.enable = lib.mkForce false;
      };
    };

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      specialArgs = {
        inputs = self.inputs // {
          inherit self;
        };
      };
      modules = [
        defaultModule
        baseModule
        extraModule
      ];
    };

  defaultEval = mkEval { };
  # The default is the two shared technosophist keys, not [ ] -- exercise the
  # opt-out explicitly rather than assuming an empty default.
  noKeysEval = mkEval { thoughtfull.user.u2fKeyFiles = lib.mkForce [ ]; };
  withKeysEval = mkEval (
    { pkgs, ... }:
    {
      thoughtfull.user.u2fKeyFiles = [
        (pkgs.writeText "fake-u2f-key-0" "handle0,pubkey0,es256,+presence+pin")
        (pkgs.writeText "fake-u2f-key-1" "handle1,pubkey1,es256,+presence+pin")
      ];
    }
  );
  # A second username exercises the "u2f keys are shared, the username isn't"
  # case the activation script needs to handle correctly.
  withKeysAndAltNameEval = mkEval (
    { pkgs, lib, ... }:
    {
      thoughtfull.user.name = lib.mkForce "jojo";
      thoughtfull.user.u2fKeyFiles = [
        (pkgs.writeText "fake-u2f-key-0" "handle0,pubkey0,es256,+presence+pin")
      ];
    }
  );

  sudoAuthorizedKeysEntry =
    defaultEval.config.environment.etc."ssh/authorized_keys.d/technosophist_sudo";
  sudoKeysContent = builtins.readFile sudoAuthorizedKeysEntry.source;

  withKeysScript = withKeysEval.config.system.activationScripts.thoughtfullU2fMappings;

  checks = [
    {
      name = "default: sudo authorized_keys.d sources sudoKeysFile (not inline text)";
      ok =
        sudoAuthorizedKeysEntry.source == defaultEval.config.thoughtfull.user.sudoKeysFile
        && sudoAuthorizedKeysEntry.text == null;
    }
    {
      name = "default: sudo authorized_keys.d content contains the default sudo keys";
      ok =
        lib.hasInfix "technosophist+sudo@ypa766" sudoKeysContent
        && lib.hasInfix "technosophist+sudo@ypc940" sudoKeysContent;
    }
    {
      name = "default: u2fKeyFiles resolves to two shared secrets, wired to matching age secrets";
      ok =
        builtins.length defaultEval.config.thoughtfull.user.u2fKeyFiles == 2
        &&
          defaultEval.config.age.secrets."u2f-key-0".file
          == builtins.elemAt defaultEval.config.thoughtfull.user.u2fKeyFiles 0
        &&
          defaultEval.config.age.secrets."u2f-key-1".file
          == builtins.elemAt defaultEval.config.thoughtfull.user.u2fKeyFiles 1;
    }
    {
      name = "default: activation script present and depends on agenixChown";
      ok =
        (defaultEval.config.system.activationScripts.thoughtfullU2fMappings.deps or [ ]) == [
          "agenixChown"
        ];
    }
    {
      name = "u2fKeyFiles = []: no u2f-key-* age secrets registered";
      ok = !(noKeysEval.config.age.secrets ? "u2f-key-0");
    }
    {
      name = "u2fKeyFiles = []: no u2f-mappings activation script";
      ok = !(noKeysEval.config.system.activationScripts ? thoughtfullU2fMappings);
    }
    {
      name = "u2fKeyFiles set: one age secret registered per file, in order";
      ok =
        withKeysEval.config.age.secrets."u2f-key-0".file
        == builtins.elemAt withKeysEval.config.thoughtfull.user.u2fKeyFiles 0
        &&
          withKeysEval.config.age.secrets."u2f-key-1".file
          == builtins.elemAt withKeysEval.config.thoughtfull.user.u2fKeyFiles 1;
    }
    {
      name = "u2fKeyFiles set: activation script depends on agenixChown";
      ok = withKeysScript.deps == [ "agenixChown" ];
    }
    {
      name = "u2fKeyFiles set: activation script joins decrypted paths with ':' and the username";
      ok =
        lib.hasInfix ''"technosophist:$(cat /run/agenix/u2f-key-0):$(cat /run/agenix/u2f-key-1)"'' withKeysScript.text
        && lib.hasInfix "/etc/u2f-mappings" withKeysScript.text
        && lib.hasInfix "chmod 0444" withKeysScript.text;
    }
    {
      name = "u2fKeyFiles set with a different username: activation script uses that host's name";
      ok = lib.hasInfix ''"jojo:$(cat /run/agenix/u2f-key-0)"'' withKeysAndAltNameEval.config.system.activationScripts.thoughtfullU2fMappings.text;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    user test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "user-test" { } "touch $out"
