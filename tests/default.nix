{ self, nixpkgs, ... }:
let
  # Build an extended pkgs that has the overlays from default.nix plus
  # lib.thoughtfull (needed by user.nix at eval time).  When using an
  # externally-created pkgs instance the module system ignores
  # nixpkgs.overlays, so all required overlays must be present here.
  # Parentheses are required: chained `.extend` without them would be parsed
  # as attribute access on the overlay lambda rather than on the pkgs result.
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
        # user.nix is unconditional; give it a name matching the default keysHash
        # so githubKeys resolves from the Nix store without a fresh network fetch.
        thoughtfull.user.name = "technosophist";
        # extendedNixpkgs is an externally-created pkgs instance; clearing
        # nixpkgs.config suppresses the assertion that fires when modules also
        # set nixpkgs.config (default.nix sets config.allowUnfree).
        nixpkgs.config = lib.mkForce { };
        # openssh.nix disables sshd-keygen because production hosts use pre-configured
        # keys; re-enable it here so the test VM can generate its own host keys.
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
