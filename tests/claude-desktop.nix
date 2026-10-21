{ self, nixpkgs, ... }:
let
  # overlays applied here because module-set nixpkgs.overlays is ignored with external pkgs
  extendedNixpkgs =
    (((nixpkgs.extend self.overlays.thoughtfull).extend self.overlays.unstable).extend self.inputs.claude-desktop.overlays.default)
    .extend
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
  name = "claude-desktop";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    machine =
      { lib, ... }:
      {
        imports = [ defaultModule ];
        # name must match the default keysHash so git.nix's githubKeys call hits the Nix store
        thoughtfull.user.name = "technosophist";
        # clear module-set nixpkgs.config to avoid the "external pkgs instance" assertion
        nixpkgs.config = lib.mkForce { };
        systemd.services.sshd-keygen.enable = lib.mkForce true;
        services.syncthing.enable = lib.mkForce false;
        services.restic.thoughtfull.enable = lib.mkForce false;
        thoughtfull = {
          claudeDesktop.enable = true;
          impermanence.enable = lib.mkForce false;
          monitoring.enable = lib.mkForce false;
        };
        virtualisation.diskSize = 8192;
      };
  };

  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    with subtest("claude-desktop runs without a bubblewrap sandbox"):
        launcher = machine.succeed("readlink -f $(which claude-desktop)").strip()
        machine.fail(f"grep -q bwrap {launcher}")

    with subtest("bwrap is available for Claude Code's sandbox"):
        machine.succeed("which bwrap")

    with subtest("Claude Code binaries downloaded by claude-desktop can run"):
        machine.succeed("${genericHello}/bin/hello")

    with subtest("claude-desktop desktop entry is installed"):
        machine.succeed("test -e /run/current-system/sw/share/applications/com.anthropic.Claude.desktop")

    with subtest("Claude Code runs git and ssh outside its sandbox"):
        settings = json.loads(machine.succeed("cat /etc/claude-code/managed-settings.json"))
        excluded = settings["sandbox"]["excludedCommands"]
        assert "git *" in excluded and "ssh *" in excluded, excluded
  '';
}
