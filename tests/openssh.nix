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
  name = "openssh";

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

    with subtest("default: sudo tries the yubikey (u2f) before ssh-agent (rssh)"):
        # Both pam_u2f and pam_rssh are "sufficient", so auth stops at whichever succeeds
        # first. The yubikey should be tried before falling back to ssh-agent (which is
        # what agent-forwarded ssh sessions rely on when no yubikey is plugged in).
        pam_sudo = machine.succeed("cat /etc/pam.d/sudo")
        print(f"/etc/pam.d/sudo:\n{pam_sudo}")

        auth_lines = [
            line
            for line in pam_sudo.splitlines()
            if "pam_u2f.so" in line or "libpam_rssh.so" in line
        ]
        assert len(auth_lines) == 2, f"expected one u2f line and one rssh line, got: {auth_lines}"

        u2f_index = next(i for i, line in enumerate(auth_lines) if "pam_u2f.so" in line)
        rssh_index = next(i for i, line in enumerate(auth_lines) if "libpam_rssh.so" in line)
        assert u2f_index < rssh_index, "pam_u2f should come before pam_rssh in /etc/pam.d/sudo"

    with subtest("default: rssh authenticates sudo against the dedicated sudo key file"):
        pam_sudo = machine.succeed("cat /etc/pam.d/sudo")
        rssh_line = next(line for line in pam_sudo.splitlines() if "libpam_rssh.so" in line)
        assert "auth_key_file=/etc/ssh/authorized_keys.d/''${ruser}_sudo" in rssh_line, (
            f"expected rssh to use the per-user sudo key file, got: {rssh_line}"
        )
  '';
}
