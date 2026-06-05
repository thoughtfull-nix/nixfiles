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
  defaultModule = import ../nixosModules/default.nix {
    inputs = self.inputs // {
      inherit self;
    };
  };
in
extendedNixpkgs.testers.nixosTest {
  name = "default";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    machine =
      { lib, ... }:
      {
        imports = [ defaultModule ];
        # name must match the default keysHash so githubKeys hits the Nix store
        thoughtfull.user.name = "technosophist";
        # clear module-set nixpkgs.config to avoid the "external pkgs instance" assertion
        nixpkgs.config = lib.mkForce { };
        # openssh.nix disables automatic keygen; re-enable for the test VM
        systemd.services.sshd-keygen.enable = lib.mkForce true;
        # Disable services that need secrets or required options not suitable for a test VM
        services.syncthing.enable = lib.mkForce false;
        services.restic.thoughtfull.enable = lib.mkForce false;
        thoughtfull = {
          impermanence.enable = lib.mkForce false;
          monitoring.enable = lib.mkForce false;
        };
      };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    with subtest("gh is in PATH"):
        machine.succeed("which gh")

    with subtest("git is in PATH"):
        machine.succeed("which git")

    with subtest("sshd is running"):
        machine.wait_for_unit("sshd.service")

    with subtest("networking domain is set"):
        hosts = machine.succeed("cat /etc/hosts")
        print(f"/etc/hosts:\n{hosts}")
        assert "thoughtfull.systems" in hosts, "networking.domain should appear in /etc/hosts"
  '';
}
