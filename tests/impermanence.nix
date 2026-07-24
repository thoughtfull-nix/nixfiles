# Lightweight nix eval check (not a nixosTest/VM boot) for the impermanence <-> restic
# exclude-path wiring: verifying config.services.restic.thoughtfull.{paths,exclude} are
# computed correctly from thoughtfull.impermanence.{directories,user.directories,user.files}
# entries' `backup`/`backupExclude` fields, and that those two fields never leak into
# environment.persistence.*.directories/files (whose upstream submodule is strict and
# rejects unknown attributes).
#
# A full nixosTest VM boot was considered and rejected: building system.build.toplevel with
# thoughtfull.impermanence.enable = true forces fileSystems."/persistent" (needs a real or
# faked filesystem), thoughtfull.impermanence.disko.* (needs disko.devices declared), and the
# rollback.nix initrd service (references a LUKS device path) -- none of which the two
# behaviors under test depend on. Because Nix is lazy, evaluating only the specific
# attributes below never forces any of that machinery.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  testUser = "testuser";
  persistentPrefix = "/persistent";

  defaultModule = import ../nixosModules/default.nix {
    inputs = self.inputs // {
      inherit self;
    };
  };

  fixture = {
    thoughtfull = {
      user.name = testUser;
      impermanence = {
        directories = [
          {
            directory = "/var/lib/example-cache";
            backup = false;
          }
          {
            directory = "/var/lib/another-cache";
            backupExclude = [ "tmp" ];
          }
        ];
        user = {
          directories = [
            {
              directory = ".minecraft";
              backupExclude = [ "cache" ];
            }
          ];
          files = [
            {
              file = ".m2/deps.jar";
              backup = false;
            }
          ];
        };
      };
    };
  };

  eval = nixosSystem {
    system = nixpkgs.stdenv.hostPlatform.system;
    lib = self.lib;
    specialArgs = {
      inputs = self.inputs // {
        inherit self;
      };
    };
    modules = [
      defaultModule
      fixture
    ];
  };

  cfg = eval.config;

  # environment.persistence's directory/file submodules are strict (no freeformType), so
  # forcing each entry's attribute names only succeeds if backup/backupExclude were stripped
  # before merging. builtins.length would only force the list spine, not each element, and so
  # would never catch a leaked attribute -- attrNames forces the per-element submodule merge,
  # where the "does not exist" rejection actually happens. tryEval turns that rejection into a
  # clean check failure instead of an uncaught eval error.
  noLeak = entries: builtins.all (d: (builtins.tryEval (builtins.attrNames d)).success) entries;

  checks = [
    {
      name = "services.restic.thoughtfull.paths defaults to the persistent storage root";
      ok = cfg.services.restic.thoughtfull.paths == [ persistentPrefix ];
    }
    {
      name = "a system directory with backup = false is excluded";
      ok = lib.elem "${persistentPrefix}/var/lib/example-cache" cfg.services.restic.thoughtfull.exclude;
    }
    {
      name = "a system directory's backupExclude sub-path is excluded";
      ok = lib.elem "${persistentPrefix}/var/lib/another-cache/tmp" cfg.services.restic.thoughtfull.exclude;
    }
    {
      name = "a user directory's backupExclude sub-path is excluded";
      ok = lib.elem "${persistentPrefix}/home/${testUser}/.minecraft/cache" cfg.services.restic.thoughtfull.exclude;
    }
    {
      name = "a user file with backup = false is excluded";
      ok = lib.elem "${persistentPrefix}/home/${testUser}/.m2/deps.jar" cfg.services.restic.thoughtfull.exclude;
    }
    {
      name = "backup/backupExclude do not leak into environment.persistence (system directories)";
      ok = noLeak cfg.environment.persistence."/persistent".directories;
    }
    {
      name = "backup/backupExclude do not leak into environment.persistence (user directories)";
      ok = noLeak cfg.environment.persistence."/persistent".users.${testUser}.directories;
    }
    {
      name = "backup does not leak into environment.persistence (user files)";
      ok = noLeak cfg.environment.persistence."/persistent".users.${testUser}.files;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    impermanence/restic exclude test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "impermanence-restic-exclude-test" { } "touch $out"
