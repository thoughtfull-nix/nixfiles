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
      { config, lib, ... }:
      {
        imports = [ defaultModule ];
        # name must match the default keysHash so git.nix's githubKeys call
        # (Host github.com's identities) hits the Nix store -- this is a full
        # VM boot, so system.build.toplevel (and thus /etc/ssh/ssh_config)
        # gets built, unlike the eval-only checks in tests/{user,openssh}.nix
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
        assertions = [
          {
            assertion = builtins.any (
              d: (d.directory or d) == ".local/share/nix"
            ) config.thoughtfull.impermanence.user.directories;
            message = "expected nix trusted-settings persistence directory .local/share/nix";
          }
        ];
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

    with subtest("nixfiles is in PATH"):
        machine.succeed("which nixfiles")

    with subtest("pins is in PATH"):
        machine.succeed("which pins")

    with subtest("uns is in PATH"):
        machine.succeed("which uns")

    with subtest("zsh is available"):
        machine.succeed("which zsh")
  '';
}
