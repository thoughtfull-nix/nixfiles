# Lightweight nix eval check (not a nixosTest/VM boot) for git.nix's rendered
# ssh_config (github.com multiplexing/identity restriction, the
# technosophist.github.com alias) and gitconfig (lfs ssh multiplexing opt-out).
#
# A VM boot was considered and rejected: no ssh connection or git operation is
# ever exercised here, only the rendered text of two config files -- both of
# which NixOS computes as plain strings (config.programs.ssh.extraConfig,
# config.environment.etc."gitconfig".text) at eval time, identical to what a
# VM's `cat /etc/ssh/ssh_config` / `cat /etc/gitconfig` would read back.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  # Importing nixosModules/git.nix requires lib.thoughtfull.githubKeys, and
  # module-set nixpkgs.overlays are ignored with external pkgs, so provide both
  # through the pkgs instance passed to nixosSystem (see tests/default.nix).
  testPkgs = (nixpkgs.extend self.overlays.thoughtfull).extend (
    _: prev: {
      lib = prev.lib.extend (_: _: { thoughtfull = self.lib.thoughtfull; });
    }
  );

  eval = nixosSystem {
    system = nixpkgs.stdenv.hostPlatform.system;
    lib = self.lib;
    pkgs = testPkgs;
    modules = [
      ../nixosModules/git.nix
      stubs.impermanence
      stubs.userAuthorizedKeyFiles
      stubs.userGithub
      {
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
      }
    ];
  };

  cfg = eval.config;
  sshConfig = cfg.programs.ssh.extraConfig;
  gitconfig = cfg.environment.etc."gitconfig".text;

  # Only github.com should be restricted to the GitHub-pulled keys; slice off
  # everything from the technosophist.github.com block onward before checking.
  githubBlock = lib.head (lib.splitString "Host technosophist.github.com" sshConfig);

  countOccurrences = needle: haystack: builtins.length (lib.splitString needle haystack) - 1;

  checks = [
    {
      name = "ssh_config multiplexes github.com connections";
      ok =
        lib.hasInfix "Host github.com" sshConfig
        && lib.hasInfix "ControlMaster auto" sshConfig
        && lib.hasInfix "ControlPath /run/user/%i/ssh-control-%n" sshConfig
        && lib.hasInfix "ControlPersist 10m" sshConfig;
    }
    {
      name = "ssh_config restricts github.com to the keys pulled from GitHub";
      ok =
        lib.hasInfix "IdentityFile /nix/store/" githubBlock
        && lib.hasInfix "IdentitiesOnly yes" githubBlock;
    }
    {
      name = "ssh_config aliases technosophist.github.com through to github.com";
      ok =
        lib.hasInfix "Host technosophist.github.com" sshConfig
        && lib.hasInfix "HostName github.com" sshConfig
        && lib.hasInfix "IdentityFile /nix/store/" sshConfig
        # Both files share this basename now (one per ypa766/ypc940 directory), so
        # two distinct nix store paths -- not one -- confirms both are offered.
        && countOccurrences "id_ed25519_sk_rk_auth_technosophist.pub" sshConfig == 2
        && lib.hasInfix "IdentitiesOnly yes" sshConfig
        && countOccurrences "ControlPersist 10m" sshConfig == 2;
    }
    {
      name = "gitconfig opts git-lfs out of its own ssh multiplexing";
      ok = lib.hasInfix "automultiplex = false" gitconfig;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    git test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}

    /etc/ssh/ssh_config:
    ${sshConfig}

    /etc/gitconfig:
    ${gitconfig}
  ''
else
  nixpkgs.runCommand "git-test" { } "touch $out"
