{ nixpkgs, self, ... }:
let
  stubs = import ./stubs.nix;

  # module-set nixpkgs.overlays are ignored with external pkgs, so apply the
  # overlay (for pkgs.thoughtfull.writeFileScriptBin, used by
  # nixosModules/git.nix) directly to the pkgs instance used by nixosTest.
  testPkgs = nixpkgs.extend self.overlays.thoughtfull;

  # Throwaway ed25519 keypairs standing in for the primary/backup FIDO2
  # signing keys. git-signing-key only ever matches on public key content, so
  # a real hardware-backed sk key isn't needed to exercise its logic.
  testKeys =
    testPkgs.runCommand "git-signing-test-keys" { nativeBuildInputs = [ testPkgs.openssh ]; }
      ''
        mkdir -p $out
        ssh-keygen -t ed25519 -N "" -C "primary-signing-test" -f $out/primary
        ssh-keygen -t ed25519 -N "" -C "backup-signing-test" -f $out/backup
      '';

  # The personal identity's signing keys are hardcoded in nixosModules/git.nix
  # to these real, committed, FIDO2-only public keys -- not configurable, so
  # unlike testKeys above there's no throwaway substitute to load a matching
  # private key for. Read directly here to check personalGitConfigFile's/
  # personalAllowedSignersFile's rendered content against the real thing.
  personalPrimarySignPub = testPkgs.lib.fileContents ../nixosModules/user/ypa766/id_ed25519_sk_rk_sign_technosophist.pub;
  personalBackupSignPub = testPkgs.lib.fileContents ../nixosModules/user/ypc940/id_ed25519_sk_rk_sign_technosophist.pub;
in
testPkgs.testers.nixosTest {
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
          stubs.userAuthorizedKeyFiles
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
        thoughtfull.programs.git = {
          signing = {
            primaryKeyFile = testKeys + "/primary.pub";
            backupKeyFile = testKeys + "/backup.pub";
          };
          personal = {
            enable = true;
            # Absolute rather than the real ~/src/technosophist/** default, so
            # the test doesn't depend on which user/HOME the VM runs commands
            # as. email/name/signing keys aren't configurable here -- they're
            # hardcoded in the module to technosophist's own.
            directory = "/tmp/personal-repos/**";
          };
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
        assert "ControlPath /run/user/%i/ssh-control-%n" in ssh_config, (
            "expected tmpfs-backed ControlPath"
        )
        assert "ControlPersist 10m" in ssh_config, "expected ControlPersist 10m"

    with subtest("ssh_config restricts github.com to the committed authorized keys"):
        ssh_config = machine.succeed("cat /etc/ssh/ssh_config")
        github_block = ssh_config.split("Host technosophist.github.com")[0]
        assert "IdentityFile /nix/store/" in github_block, (
            "expected github.com identities to point at nix store paths built from "
            "the committed authorizedKeyFiles"
        )
        # Both files share this basename now (one per ypa766/ypc940 directory), so
        # two distinct nix store paths -- not one -- confirms both are offered.
        assert github_block.count("id_ed25519_sk_rk_auth_technosophist.pub") == 2, (
            "expected both authorized ssh public keys as identities"
        )
        assert "IdentitiesOnly yes" in github_block, (
            "expected github.com to restrict to only the committed authorized keys"
        )

    with subtest("ssh_config hardcodes technosophist.github.com to technosophist's own auth keys"):
        ssh_config = machine.succeed("cat /etc/ssh/ssh_config")
        assert "Host technosophist.github.com" in ssh_config, (
            "expected a technosophist.github.com ssh host block"
        )
        assert "HostName github.com" in ssh_config, (
            "expected technosophist.github.com to forward through to github.com"
        )
        technosophist_block = ssh_config.split("Host technosophist.github.com")[1]
        assert "IdentityFile /nix/store/" in technosophist_block, (
            "expected technosophist.github.com identities to point at nix store paths"
        )
        # Same basename check as github.com above -- confirms both of technosophist's
        # own auth keys are offered, hardcoded, independent of authorizedKeyFiles.
        assert technosophist_block.count("id_ed25519_sk_rk_auth_technosophist.pub") == 2, (
            "expected both of technosophist's own authorized ssh public keys as identities"
        )
        assert "IdentitiesOnly yes" in technosophist_block, (
            "expected technosophist.github.com to restrict to only its hardcoded keys"
        )
        assert "ControlPath /run/user/%i/ssh-control-%n" in ssh_config, (
            "expected technosophist.github.com to have its own ControlMaster socket"
        )
        assert ssh_config.count("ControlPersist 10m") == 2, (
            "expected both github.com and technosophist.github.com to persist for 10m"
        )

    with subtest("gitconfig opts git-lfs out of its own ssh multiplexing"):
        gitconfig = machine.succeed("cat /etc/gitconfig")
        print(f"/etc/gitconfig:\n{gitconfig}")
        assert "automultiplex = false" in gitconfig, "expected lfs.ssh.automultiplex = false"

    with subtest("gitconfig enables ssh commit signing via git-signing-key"):
        gitconfig = machine.succeed("cat /etc/gitconfig")
        assert "gpgsign = true" in gitconfig, "expected commit.gpgsign = true"
        assert 'format = "ssh"' in gitconfig, "expected gpg.format = ssh"
        assert 'defaultKeyCommand = "git-signing-key"' in gitconfig, (
            "expected gpg.ssh.defaultKeyCommand = git-signing-key"
        )
        assert 'allowedSignersFile = "/nix/store/' in gitconfig, (
            "expected gpg.ssh.allowedSignersFile to point at a nix store path"
        )

    with subtest("allowed_signers lists the configured email against both signing keys"):
        gitconfig = machine.succeed("cat /etc/gitconfig")
        allowed_signers_path = [
            line.split("=", 1)[1].strip().strip('"')
            for line in gitconfig.splitlines()
            if line.strip().startswith("allowedSignersFile")
        ][0]
        allowed_signers = machine.succeed(f"cat {allowed_signers_path}")
        print(f"allowed_signers:\n{allowed_signers}")
        primary_pub = machine.succeed("cat ${testKeys}/primary.pub").strip()
        backup_pub = machine.succeed("cat ${testKeys}/backup.pub").strip()
        for line in allowed_signers.splitlines():
            assert "test@example.com" in line and 'namespaces="git"' in line, (
                f"expected every allowed_signers line to allow test@example.com for git, got: {line!r}"
            )
        assert primary_pub in allowed_signers, "expected the primary key in allowed_signers"
        assert backup_pub in allowed_signers, "expected the backup key in allowed_signers"

    # ssh-add refuses private keys that are group/world readable, but files in
    # the nix store are always world-readable, so each private test key is
    # copied out to a 0600 tmpfile before being loaded into the agent.
    with subtest("git-signing-key selects the backup key when only it is loaded"):
        out = machine.succeed(
            "ssh-agent bash -c '"
            "cp ${testKeys}/backup /tmp/backup && chmod 600 /tmp/backup && "
            "ssh-add /tmp/backup >/dev/null 2>&1 && git-signing-key'"
        )
        backup_pub = machine.succeed("cat ${testKeys}/backup.pub").strip()
        assert out.strip() == f"key::{backup_pub}", (
            f"expected the backup key to be selected, got: {out!r}"
        )

    with subtest("git-signing-key prefers the primary key when both are loaded"):
        out = machine.succeed(
            "ssh-agent bash -c '"
            "cp ${testKeys}/primary /tmp/primary && chmod 600 /tmp/primary && "
            "cp ${testKeys}/backup /tmp/backup && chmod 600 /tmp/backup && "
            "ssh-add /tmp/primary >/dev/null 2>&1 && "
            "ssh-add /tmp/backup >/dev/null 2>&1 && git-signing-key'"
        )
        primary_pub = machine.succeed("cat ${testKeys}/primary.pub").strip()
        assert out.strip() == f"key::{primary_pub}", (
            f"expected the primary key to be selected, got: {out!r}"
        )

    with subtest("git-signing-key fails when neither key is loaded"):
        machine.fail("ssh-agent bash -c 'git-signing-key'")

    # End-to-end: a real commit, signed via defaultKeyCommand and verified
    # against allowed_signers. Ed25519 can't exercise a FIDO2 key's touch/PIN
    # prompt, but that's OpenSSH's concern, not this module's -- the module
    # only cares that the right pubkey ends up offered and accepted.
    with subtest("a commit signed via git-signing-key verifies against allowed_signers"):
        machine.succeed(
            "ssh-agent bash -c '"
            "cp ${testKeys}/primary /tmp/primary && chmod 600 /tmp/primary && "
            "ssh-add /tmp/primary >/dev/null 2>&1 && "
            "rm -rf /tmp/repo && git init -q /tmp/repo && cd /tmp/repo && "
            "git commit -q --allow-empty -m signed && "
            "git verify-commit HEAD'"
        )

    with subtest("gitconfig includeIf's the personal directory to a personal gitconfig"):
        gitconfig = machine.succeed("cat /etc/gitconfig")
        assert 'includeIf "gitdir:/tmp/personal-repos/**"' in gitconfig, (
            "expected an includeIf block for the personal directory"
        )
        include_block = gitconfig.split('includeIf "gitdir:/tmp/personal-repos/**"')[1]
        personal_gitconfig_path = [
            line.split("=", 1)[1].strip().strip('"')
            for line in include_block.splitlines()
            if line.strip().startswith("path")
        ][0]
        assert personal_gitconfig_path.startswith("/nix/store/"), (
            "expected the personal gitconfig path to be a nix store path"
        )

    with subtest("the personal gitconfig hardcodes technosophist's own identity and signing"):
        personal_gitconfig = machine.succeed(f"cat {personal_gitconfig_path}")
        print(f"personal gitconfig:\n{personal_gitconfig}")
        assert 'email = "technosophist@thoughtfull.systems"' in personal_gitconfig, (
            "expected the personal identity's hardcoded email"
        )
        assert 'name = "technosophist"' in personal_gitconfig, (
            "expected the personal identity's hardcoded name"
        )
        assert "gpgsign = true" in personal_gitconfig, "expected commit.gpgsign = true"
        assert 'format = "ssh"' in personal_gitconfig, "expected gpg.format = ssh"
        assert 'defaultKeyCommand = "git-signing-key-personal"' in personal_gitconfig, (
            "expected gpg.ssh.defaultKeyCommand = git-signing-key-personal"
        )
        assert 'allowedSignersFile = "/nix/store/' in personal_gitconfig, (
            "expected gpg.ssh.allowedSignersFile to point at a nix store path"
        )
        personal_allowed_signers_path = [
            line.split("=", 1)[1].strip().strip('"')
            for line in personal_gitconfig.splitlines()
            if line.strip().startswith("allowedSignersFile")
        ][0]
        assert personal_allowed_signers_path != allowed_signers_path, (
            "expected the personal allowed_signers file to be distinct from the main one"
        )

    with subtest("the personal allowed_signers file hardcodes technosophist's own sign keys"):
        personal_allowed_signers = machine.succeed(f"cat {personal_allowed_signers_path}")
        print(f"personal allowed_signers:\n{personal_allowed_signers}")
        for line in personal_allowed_signers.splitlines():
            assert "technosophist@thoughtfull.systems" in line and 'namespaces="git"' in line, (
                f"expected every line to allow technosophist@thoughtfull.systems for git, got: {line!r}"
            )
        assert "${personalPrimarySignPub}".strip() in personal_allowed_signers, (
            "expected technosophist's real committed primary sign key in the personal "
            "allowed_signers"
        )
        assert "${personalBackupSignPub}".strip() in personal_allowed_signers, (
            "expected technosophist's real committed backup sign key in the personal "
            "allowed_signers"
        )
        assert "test@example.com" not in personal_allowed_signers, (
            "the main identity's email must not appear in the personal allowed_signers"
        )
        assert primary_pub not in personal_allowed_signers, (
            "the main identity's primary key must not appear in the personal allowed_signers"
        )

    with subtest("git-signing-key-personal embeds technosophist's real committed sign keys"):
        script_path = machine.succeed("readlink -f $(which git-signing-key-personal)").strip()
        script_contents = machine.succeed(f"cat {script_path}")
        assert "${personalPrimarySignPub}".strip() in script_contents, (
            "expected the primary sign key embedded in git-signing-key-personal"
        )
        assert "${personalBackupSignPub}".strip() in script_contents, (
            "expected the backup sign key embedded in git-signing-key-personal"
        )

    with subtest("git-signing-key-personal fails when neither personal key is loaded"):
        machine.fail("ssh-agent bash -c 'git-signing-key-personal'")

    # Identity resolution (not signing -- technosophist's real sign keys are
    # FIDO2-hardware-only, unavailable in a VM) for a repo under the personal
    # directory vs. one outside it.
    with subtest("a repo under the personal directory resolves the personal identity"):
        out = machine.succeed(
            "rm -rf /tmp/personal-repos/repo && "
            "git init -q -b main /tmp/personal-repos/repo && "
            "git -C /tmp/personal-repos/repo config user.email"
        )
        assert out.strip() == "technosophist@thoughtfull.systems", (
            f"expected the personal email under the personal directory, got: {out!r}"
        )

    with subtest("a repo outside the personal directory still uses the main identity"):
        out = machine.succeed("git -C /tmp/repo config user.email")
        assert out.strip() == "test@example.com", (
            f"expected the main identity's email outside the personal directory, got: {out!r}"
        )
  '';
}
