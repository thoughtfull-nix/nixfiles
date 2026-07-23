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

    with subtest("ssh_config aliases technosophist.github.com through to github.com"):
        ssh_config = machine.succeed("cat /etc/ssh/ssh_config")
        assert "Host technosophist.github.com" in ssh_config, (
            "expected a technosophist.github.com ssh host block"
        )
        assert "HostName github.com" in ssh_config, (
            "expected technosophist.github.com to forward through to github.com"
        )
        assert "IdentityFile ~/.ssh/id_ed25519_sk_ypa766_auth" in ssh_config, (
            "expected first authorized ssh key as an identity"
        )
        assert "IdentityFile ~/.ssh/id_ed25519_sk_ypc940_auth" in ssh_config, (
            "expected second authorized ssh key as an identity"
        )
        assert "IdentitiesOnly yes" in ssh_config, (
            "expected technosophist.github.com to restrict to only its configured keys"
        )
        assert "ControlPath /run/user/%i/ssh-control-%n-%C" in ssh_config, (
            "expected technosophist.github.com to have its own ControlMaster socket"
        )
        assert ssh_config.count("ControlPersist 10m") == 2, (
            "expected both github.com and technosophist.github.com to persist for 10m"
        )

    with subtest("gitconfig opts git-lfs out of its own ssh multiplexing"):
        gitconfig = machine.succeed("cat /etc/gitconfig")
        print(f"/etc/gitconfig:\n{gitconfig}")
        assert "automultiplex = false" in gitconfig, "expected lfs.ssh.automultiplex = false"
  '';
}
