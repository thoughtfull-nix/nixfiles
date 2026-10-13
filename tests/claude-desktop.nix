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

  # The wrapper ends by exec'ing bwrap with container-init (which runs Claude
  # Desktop); swap that for a probe command to inspect the sandbox it builds.
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    machine.succeed(
        "sed -E 's|^ *[^ ]+-container-init \"\\$@\"$|  \"\\$@\"|' "
        "$(readlink -f $(which claude-desktop)) > /tmp/sandbox && chmod +x /tmp/sandbox"
    )

    with subtest("sandbox sees the host ssh_config"):
        machine.succeed("/tmp/sandbox cat /etc/ssh/ssh_config | grep -q 'Host github.com'")

    with subtest("ssh in the sandbox applies the host config"):
        out = machine.succeed("/tmp/sandbox ssh -G github.com")
        assert "controlpersist 10800" in out, out

    with subtest("sandbox sees the host known hosts"):
        machine.succeed("/tmp/sandbox test -e /etc/ssh/ssh_known_hosts")
  '';
}
