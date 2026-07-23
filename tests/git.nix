{ nixpkgs, ... }:
let
  stubs = import ./stubs.nix;
in
nixpkgs.testers.nixosTest {
  name = "git";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    machine =
      { ... }:
      {
        imports = [
          ../nixosModules/git.nix
          stubs.impermanence
        ];
        programs.git = {
          enable = true;
          config = {
            user.name = "test";
            user.email = "test@example.com";
            # Mirror the aegle host config so the git-lfs multiplexing opt-out is
            # exercised end to end.
            lfs.ssh.automultiplex = false;
          };
          lfs.enable = true;
        };
      };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    with subtest("ssh_config multiplexes github.com connections"):
        ssh_config = machine.succeed("cat /etc/ssh/ssh_config")
        print(f"/etc/ssh/ssh_config:\n{ssh_config}")
        assert "Host github.com" in ssh_config, "expected a github.com ssh host block"
        assert "ControlMaster auto" in ssh_config, "expected ControlMaster auto"
        assert "ControlPath /run/user/%i/ssh-control-%C" in ssh_config, (
            "expected tmpfs-backed ControlPath"
        )
        assert "ControlPersist 10m" in ssh_config, "expected ControlPersist 10m"

    with subtest("gitconfig opts git-lfs out of its own ssh multiplexing"):
        gitconfig = machine.succeed("cat /etc/gitconfig")
        print(f"/etc/gitconfig:\n{gitconfig}")
        assert "automultiplex = false" in gitconfig, "expected lfs.ssh.automultiplex = false"
  '';
}
