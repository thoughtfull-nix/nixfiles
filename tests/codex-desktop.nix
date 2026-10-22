{ self, nixpkgs, ... }:
let
  # overlays applied here because module-set nixpkgs.overlays is ignored with external pkgs
  extendedNixpkgs =
    ((nixpkgs.extend self.overlays.thoughtfull).extend self.overlays.unstable).extend
      (
        _: prev: {
          lib = prev.lib.extend (_: _: { thoughtfull = self.lib.thoughtfull; });
        }
      );
  genericHello = import ./generic-hello.nix nixpkgs;
  defaultModule = import ../nixosModules/default.nix {
    inputs = self.inputs // {
      inherit self;
    };
  };
in
extendedNixpkgs.testers.nixosTest {
  name = "codex-desktop";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    machine =
      { config, lib, ... }:
      {
        imports = [ defaultModule ];
        assertions = [
          {
            assertion =
              lib.all
                (d: builtins.elem d (map (d: d.directory or d) config.thoughtfull.impermanence.user.directories))
                [
                  ".cache/codex-runtimes"
                  ".codex"
                  ".config/Codex"
                  ".config/codex-desktop"
                  ".local/state/codex-desktop"
                ];
            message = "expected Codex Desktop state directories to be persisted";
          }
          {
            assertion =
              let
                excludes = builtins.concatMap (
                  d: map (sub: "${d.directory}/${sub}") (d.backupExclude or [ ])
                ) config.thoughtfull.impermanence.user.directories;
              in
              lib.all (e: builtins.elem e excludes) [
                ".codex/cache"
                ".codex/plugins/cache"
                ".config/Codex/**/GPUCache"
                ".config/Codex/component_crx_cache"
              ];
            message = "expected Codex Desktop caches excluded from backups";
          }
          {
            assertion =
              builtins.elem "https://codex-desktop-linux.cachix.org" config.nix.settings.extra-substituters
              && builtins.elem "codex-desktop-linux.cachix.org-1:nX/xy6AdK9hQE24A8ALGjkCKj2ObFmcnemiL5Cid4nk=" config.nix.settings.extra-trusted-public-keys;
            message = "expected codex-desktop-linux cache trusted when Codex Desktop is enabled";
          }
        ];
        # name must match the default keysHash so git.nix's githubKeys call hits the Nix store
        thoughtfull.user.name = "technosophist";
        # clear module-set nixpkgs.config to avoid the "external pkgs instance" assertion
        nixpkgs.config = lib.mkForce { };
        systemd.services.sshd-keygen.enable = lib.mkForce true;
        services.syncthing.enable = lib.mkForce false;
        services.restic.thoughtfull.enable = lib.mkForce false;
        thoughtfull = {
          codexDesktop.enable = true;
          impermanence.enable = lib.mkForce false;
          monitoring.enable = lib.mkForce false;
        };
        virtualisation.diskSize = 8192;
      };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    with subtest("codex-desktop is installed"):
        machine.succeed("which codex-desktop")

    with subtest("codex-desktop desktop entry is installed"):
        machine.succeed("test -e /run/current-system/sw/share/applications/codex-desktop.desktop")

    with subtest("generic Linux runtimes downloaded by codex-desktop can run"):
        machine.succeed("${genericHello}/bin/hello")
  '';
}
