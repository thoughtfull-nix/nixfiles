{ self, nixpkgs, ... }:
let
  # Overlays applied directly (not via the `nixpkgs.overlays` module option) so the same `pkgs`
  # can also build fixture derivations (a custom `nixfiles` build with stubbed disko, an SSH
  # test keypair, a pre-encrypted shared secret) outside of any node.
  pkgs = nixpkgs.extend self.overlays.thoughtfull;
  inherit (pkgs) lib;

  # SSH keypair so `personal` can reach `target` without a real Yubikey/ssh-agent.
  testSshKey = pkgs.runCommand "test-ssh-key" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -t ed25519 -N "" -C "test" -f $out/id_ed25519
  '';

  # Stand-in for the real (FIDO2, resident) dedicated signing keypair `provision` points
  # `user.signingkey` at
  # (nixosModules/user/ypa766/id_ed25519_sk_rk_sign_technosophist.pub) -- a plain keypair
  # here since the module's/script's signing logic is key-format-agnostic, and no FIDO2
  # hardware is available in a VM. Its private half is loaded into the (real) ssh-agent
  # `provision` starts, standing in for `ssh-add -K` downloading the resident credential, so
  # the bootstrap commit carries a real, verifiable SSH signature end-to-end.
  testSigningKey = pkgs.runCommand "test-signing-key" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -t ed25519 -N "" -C "test-signing" -f $out/id_ed25519
  '';

  # Stand-in for the backup signing keypair
  # (nixosModules/user/ypc940/id_ed25519_sk_rk_sign_technosophist.pub). Distinct from
  # testSigningKey so its pubkey content can never coincidentally match what's loaded in
  # ssh-agent -- provision's "primary preferred" scenario below should never fall back to it.
  testBackupSigningKey =
    pkgs.runCommand "test-backup-signing-key" { nativeBuildInputs = [ pkgs.openssh ]; }
      ''
        mkdir -p $out
        ssh-keygen -t ed25519 -N "" -C "test-backup-signing" -f $out/id_ed25519
      '';

  # Stand-in for master-recipients.txt / master-identities.txt. `remote-provision` only ever
  # *encrypts* against master-recipients.txt in this flow (LUKS/user passphrase secrets are
  # write-only for a brand-new host) -- the identity half is never exercised here.
  testAgeKey = pkgs.runCommand "test-age-key" { nativeBuildInputs = [ pkgs.age ]; } ''
    mkdir -p $out
    age-keygen -o $out/identity.txt 2>$out/keygen.log
    grep "Public key:" $out/keygen.log | sed 's/.*Public key: //' >$out/recipient.txt
  '';

  # A pre-existing shared secret, standing in for a repo that already has other hosts.
  # `remote-provision`'s `rekey <hostname>` call must re-encrypt this to include the new host's
  # pubkey, so `finish-remote-provision` can later decrypt it using *only* the host's own
  # just-installed key -- never the master identity.
  #
  # The decrypted content is a complete nix.conf line (matching how nixosModules/github-token.nix
  # consumes it via `!include`), not a bare token -- finish-remote-provision writes it into
  # /root/.config/nix/nix.conf as-is.
  fakeGithubToken = "ghp_faketoken0000000000000000000000";
  fakeGithubTokenLine = "access-tokens = github.com=${fakeGithubToken}";
  githubTokenSecret =
    pkgs.runCommand "github-access-token.age"
      {
        nativeBuildInputs = [ pkgs.age ];
      }
      ''
        echo -n "${fakeGithubTokenLine}" | age -e -R ${testAgeKey}/recipient.txt -o $out
      '';

  bootstrapNixFile = pkgs.writeText "bootstrap.nix" (
    builtins.readFile ../nixosConfigurations/bootstrap.nix
  );

  # Record disko's invocation instead of touching a real disk. Fails loudly if the github access
  # token hasn't already been written by that point -- this is the ordering
  # `finish-remote-provision` must get right, since evaluating any nixosConfigurations.<host>
  # (which a real `disko --mode ... --flake ...#<host>` would do) forces a fetch of the private
  # `kryptonix` flake input. (/etc/nix/nix.conf is a symlink into the read-only Nix store on any
  # NixOS system, so the token goes to root's own writable /root/.config/nix/nix.conf instead --
  # this stub always runs as root via sudo, same as the real disko/nixos-install invocations.)
  stubDisko = pkgs.writeShellScriptBin "disko" ''
    echo "disko $*" >>/tmp/stub-calls.log
    grep -q "access-tokens.*github.com" /root/.config/nix/nix.conf 2>/dev/null || {
      echo "disko stub: github token missing from /root/.config/nix/nix.conf at disko time" >&2
      exit 1
    }
    exit 0
  '';

  # Placeholders shared by every `nixfiles` test build; each build below overrides only the
  # handful of commands (disko, ssh-add) it needs to stub differently.
  commonNixfilesArgs = {
    age = "${pkgs.age}/bin/age";
    git = "${pkgs.git}/bin/git";
    phraze = "${pkgs.phraze}/bin/phraze";
    raspberrypi-firmware = "";
    ssh-agent = "${pkgs.openssh}/bin/ssh-agent";
    uboot-rpi4 = "";
  };

  testNixfiles = pkgs.thoughtfull.writeArgcScript "nixfiles" ../packages/nixfiles.bash (
    commonNixfilesArgs
    // {
      disko = "${stubDisko}/bin/disko";
      ssh-add = "${pkgs.openssh}/bin/ssh-add";
    }
  );

  # `provision` loads a resident SSH credential via `ssh-add -K`, unavailable in a VM. Stand in
  # for the real hardware by loading `testSigningKey`'s private half for real instead, so the
  # subsequent `git config user.signingkey`/`git commit` steps have a real credential to sign
  # with in the (real) ssh-agent `provision` starts -- letting the bootstrap commit end up with an
  # actual, verifiable SSH signature. ssh-add refuses to load a private key with the world-
  # readable permissions every nix store path has, so stage a copy with 0600 first.
  stubSshAddLoadTestSigningKey = pkgs.writeShellScriptBin "ssh-add" ''
    set -euo pipefail
    if [[ "''${1:-}" == "-K" ]]; then
      key=$(mktemp)
      cp ${testSigningKey}/id_ed25519 "$key"
      chmod 600 "$key"
      exec ${pkgs.openssh}/bin/ssh-add "$key"
    fi
    exec ${pkgs.openssh}/bin/ssh-add "$@"
  '';

  # `provision` (unlike `finish-remote-provision`) never writes a github access token anywhere --
  # it has no equivalent token-forwarding step of its own -- so it needs a disko stub without
  # that check.
  stubDiskoForProvision = pkgs.writeShellScriptBin "disko" ''
    echo "disko $*" >>/tmp/stub-calls.log
    exit 0
  '';

  testNixfilesForProvision = pkgs.thoughtfull.writeArgcScript "nixfiles" ../packages/nixfiles.bash (
    commonNixfilesArgs
    // {
      disko = "${stubDiskoForProvision}/bin/disko";
      ssh-add = "${stubSshAddLoadTestSigningKey}/bin/ssh-add";
    }
  );

  # The email `git config user.email` ends up as, hardcoded in nixfiles.bash's own
  # `git_user_email` -- not something the test can override -- so the allowed_signers file used
  # to verify the bootstrap commit's signature below has to match it.
  testAllowedSigners = pkgs.writeText "test-allowed-signers" ''
    technosophist@thoughtfull.systems namespaces="git" ${lib.fileContents "${testSigningKey}/id_ed25519.pub"}
  '';

  # Stub the handful of destructive/hardware-specific commands `finish-remote-provision`
  # dispatches on the target, so the test exercises the script's own orchestration logic
  # (sequencing, file placement, secret handling) without a real disk or a fully-evaluable flake.
  # `lib.hiPrio` ensures these win over anything else that might land on PATH.
  stubNixosGenerateConfig = lib.hiPrio (
    pkgs.writeShellScriptBin "nixos-generate-config" ''
      cat <<'HWCONFIG'
      { modulesPath, ... }:
      {
        imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
        boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" ];
        nixpkgs.hostPlatform = "x86_64-linux";
      }
      HWCONFIG
    ''
  );

  stubNixosInstall = lib.hiPrio (
    pkgs.writeShellScriptBin "nixos-install" ''
      echo "nixos-install $*" >>/tmp/stub-calls.log
      exit 0
    ''
  );

  stubCryptenroll = lib.hiPrio (
    pkgs.writeShellScriptBin "systemd-cryptenroll" ''
      echo "systemd-cryptenroll $*" >>/tmp/stub-calls.log
      echo fido2
      exit 0
    ''
  );

  stubBlkid = lib.hiPrio (
    pkgs.writeShellScriptBin "blkid" ''
      echo "/dev/vdb2"
    ''
  );

  stubNix = lib.hiPrio (
    pkgs.writeShellScriptBin "nix" ''
      set -euo pipefail
      echo "nix $*" >>/tmp/stub-calls.log
      git -C /root/nixfiles-fixture diff --cached --name-only |
        grep -Fx nixosConfigurations/test-host.nix
      git -C /root/nixfiles-fixture diff --cached --name-only |
        grep -Fx nixosConfigurations/test-host/hardware-configuration.nix
      echo /nix/store/test-host-system.drv
    ''
  );
in
pkgs.testers.nixosTest {
  name = "nixfiles";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    # Stands in for the already-configured personal laptop: git identity is set up, but
    # deliberately no SSH signing key/Yubikey -- `remote-provision` must not need one.
    personal =
      { ... }:
      {
        environment.systemPackages = [
          testNixfiles
          pkgs.git
          stubNix
          pkgs.whois # mkpasswd, used by ensure-secret for the hashed user passphrase
        ];
        services.openssh.enable = true;
      };

    # Stands in for the work laptop, booted from a vanilla NixOS ISO and reachable over SSH
    # (console `passwd`/authorized_keys step already done). Also serves the fixture repo
    # anonymously over git://, standing in for a public GitHub clone.
    target =
      { ... }:
      {
        environment.systemPackages = [
          testNixfiles
          pkgs.age
          pkgs.git
          stubNixosGenerateConfig
          stubNixosInstall
          stubCryptenroll
          stubBlkid
        ];
        services.openssh = {
          enable = true;
          settings.PermitRootLogin = "yes";
        };
        users.users.root.openssh.authorizedKeys.keyFiles = [ "${testSshKey}/id_ed25519.pub" ];
        # remote-provision's ssh delivery lands the host key as root (0600); finish-remote-provision
        # is run by a different, unprivileged console user here (matching a real installer login),
        # to catch ownership mismatches on that handoff.
        users.users.operator = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
        };
        security.sudo.wheelNeedsPassword = false;
        # git-daemon.service needs /srv/git to exist at boot; the bare repo itself is created
        # later in the test script.
        systemd.tmpfiles.rules = [ "d /srv/git 0755 root root - -" ];
        services.gitDaemon = {
          enable = true;
          basePath = "/srv/git";
          exportAll = true;
        };
        # git-daemon runs as its own unprivileged user; without this it refuses to serve a
        # repository owned by root (the "detected dubious ownership" safe.directory check).
        environment.etc."gitconfig".text = ''
          [safe]
            directory = /srv/git/nixfiles.git
        '';
      };

    # Stands in for the fully-console-based `provision` flow: everything (Yubikey SSH bootstrap
    # stubbed, disk formatting, commit, install) happens on one machine, no personal laptop or
    # network involved.
    standalone =
      { ... }:
      {
        environment.systemPackages = [
          testNixfilesForProvision
          pkgs.age
          pkgs.git
          pkgs.whois # mkpasswd, used by ensure-secret for the hashed user passphrase
          stubNixosGenerateConfig
          stubNixosInstall
          stubCryptenroll
          stubBlkid
        ];
      };
  };

  testScript = ''
    start_all()
    personal.wait_for_unit("multi-user.target")
    target.wait_for_unit("sshd.service")
    target.wait_for_unit("git-daemon.service")
    standalone.wait_for_unit("multi-user.target")

    with subtest("personal can reach target over ssh"):
        personal.succeed("mkdir -p -m 700 /root/.ssh")
        personal.copy_from_host("${testSshKey}/id_ed25519", "/root/.ssh/id_ed25519")
        personal.succeed("chmod 600 /root/.ssh/id_ed25519")
        personal.succeed(
            "ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes root@target true"
        )

    with subtest("seed the fixture repo, standing in for an existing nixfiles checkout"):
        target.succeed("git init --bare /srv/git/nixfiles.git")
        personal.succeed(
            "git init -b main /root/nixfiles-fixture && "
            "git -C /root/nixfiles-fixture config user.name test && "
            "git -C /root/nixfiles-fixture config user.email test@example.com && "
            "mkdir -p /root/nixfiles-fixture/nixosConfigurations/shared/secrets"
        )
        personal.copy_from_host(
            "${bootstrapNixFile}", "/root/nixfiles-fixture/nixosConfigurations/bootstrap.nix"
        )
        personal.copy_from_host(
            "${testAgeKey}/recipient.txt", "/root/nixfiles-fixture/master-recipients.txt"
        )
        personal.copy_from_host("${testAgeKey}/identity.txt", "/root/master-identity.txt")
        personal.copy_from_host(
            "${githubTokenSecret}",
            "/root/nixfiles-fixture/nixosConfigurations/shared/secrets/github-access-token.age",
        )
        personal.succeed(
            "git -C /root/nixfiles-fixture add . && "
            "git -C /root/nixfiles-fixture commit -m 'seed fixture' && "
            "git -C /root/nixfiles-fixture remote add origin root@target:/srv/git/nixfiles.git && "
            "git -C /root/nixfiles-fixture push origin HEAD:main"
        )

    with subtest("remote-provision runs entirely from personal, dispatching over ssh to target"):
        log = personal.succeed(
            "(yes yes || true) | nixfiles remote-provision test-host root@target "
            "--nixfiles-path=/root/nixfiles-fixture --nixfiles-git-branch=main "
            "--age-identity=/root/master-identity.txt "
            "--disk-device=/dev/vdb --boot-size=512M --swap-size=1G "
            "2>&1"
        )
        print(f"remote-provision output:\n{log}")

    with subtest("remote-provision evaluates the generated host configuration"):
        personal.succeed(
            "grep -Fx 'nix eval --raw --no-write-lock-file "
            "/root/nixfiles-fixture#nixosConfigurations.test-host.config.system.build.toplevel.drvPath' "
            "/tmp/stub-calls.log"
        )

    with subtest("a real (stubbed) hardware-configuration.nix was generated over ssh, not locally"):
        hwconfig = personal.succeed(
            "cat /root/nixfiles-fixture/nixosConfigurations/test-host/hardware-configuration.nix"
        )
        print(f"hardware-configuration.nix:\n{hwconfig}")
        assert "virtio_blk" in hwconfig, (
            "hardware-configuration.nix should reflect nixos-generate-config run on the target, "
            "not the personal laptop"
        )

    with subtest("disk device/size prompts were written into the generated host config"):
        hostnix = personal.succeed(
            "cat /root/nixfiles-fixture/nixosConfigurations/test-host.nix"
        )
        normalized_hostnix = " ".join(hostnix.split())
        print(f"test-host.nix:\n{hostnix}")
        assert '"/dev/vdb"' in hostnix
        assert '"512M"' in hostnix
        assert '"1G"' in hostnix
        assert "# encrypted.device" not in hostnix, (
            "the disko block should no longer be a commented-out placeholder"
        )
        assert (
            "services.syncthing.thoughtfull.passwordFile = "
            "./test-host/secrets/syncthing-passphrase.age;"
        ) in normalized_hostnix

    with subtest("the private ssh host key was delivered directly to target, not via a repo secret"):
        target.succeed("test -f /tmp/ssh_host_ed25519_key")
        perms = target.succeed("stat -c %a /tmp/ssh_host_ed25519_key").strip()
        assert perms == "600", f"expected 0600, got {perms}"
        target.fail(
            "find /root -iname '*ssh-host-key*' | grep ."
        )  # no passphrase-wrapped key secret should exist anywhere on target

    # `target` only hosts the *bare* repo (standing in for GitHub) -- it has no working-copy
    # clone of its own yet, so read fixture contents straight out of the bare repo via
    # `git show`, exactly as `finish-remote-provision`'s own clone will see them.
    with subtest("host-specific secrets are decryptable with the new host's own transferred key"):
        for secret in [
            "luks-recovery-passphrase",
            "hashed-user-passphrase",
            "syncthing-passphrase",
        ]:
            target.succeed(
                f"git --git-dir=/srv/git/nixfiles.git show "
                f"main:nixosConfigurations/test-host/secrets/{secret}.age "
                f"| age -d -i /tmp/ssh_host_ed25519_key"
            )

    with subtest("rekey extended the shared github token secret to the new host"):
        decrypted = target.succeed(
            "git --git-dir=/srv/git/nixfiles.git show "
            "main:nixosConfigurations/shared/secrets/github-access-token.age "
            "| age -d -i /tmp/ssh_host_ed25519_key"
        ).strip()
        assert decrypted == "${fakeGithubTokenLine}", (
            f"expected the fixture token line, got {decrypted!r} -- rekey should have added the "
            "new host as a recipient during remote-provision"
        )

    with subtest("finish-remote-provision runs locally on target, no commit access needed"):
        # finish-remote-provision does its own read-only clone of the (fixture) repo -- no
        # separate `git clone` should be needed here. Run as "operator", a different user than
        # remote-provision's ssh delivery used (root), to exercise the ownership handoff on
        # /tmp/ssh_host_ed25519_key rather than trivially succeeding because both sides happen
        # to be root.
        log = target.succeed(
            "su - operator -c "
            "'(yes yes || true) | nixfiles finish-remote-provision test-host "
            "--nixfiles-git-url=git://target/nixfiles.git --nixfiles-git-branch=main' "
            "2>&1"
        )
        print(f"finish-remote-provision output:\n{log}")
        # The disko stub itself fails loudly if /root/.config/nix/nix.conf doesn't already
        # carry the github token when it runs -- finish-remote-provision succeeding above
        # already proves that ordering requirement held.

    with subtest("nix.conf got the token line verbatim, not re-wrapped in another prefix"):
        nix_conf = target.succeed("cat /root/.config/nix/nix.conf")
        print(f"/root/.config/nix/nix.conf:\n{nix_conf}")
        assert nix_conf.strip() == "${fakeGithubTokenLine}", (
            f"expected exactly the decrypted line, got {nix_conf!r} -- finish-remote-provision "
            "must write the secret's content as-is, not wrap it in another access-tokens prefix"
        )

    with subtest("stubbed disko and nixos-install were invoked with the right flake/hostname"):
        calls = target.succeed("cat /tmp/stub-calls.log")
        print(f"stub calls:\n{calls}")
        assert "disko" in calls and "test-host" in calls
        assert "nixos-install" in calls and "--no-root-password" in calls
        assert calls.index("disko") < calls.index("nixos-install"), (
            "disko must run before nixos-install"
        )

    # `provision` is the original, still-maintained console/Yubikey flow: unlike remote-provision,
    # it runs entirely on one machine and bootstraps its own git SSH signing setup by cloning the
    # repo fresh. Seed a bare "origin" repo (standing in for GitHub) with fixture content,
    # including a stand-in signing pubkey at the path the real repo carries one
    # (nixosModules/user/ypa766/id_ed25519_sk_rk_sign_technosophist.pub), for provision to
    # clone from and push back to -- exercising its clone+signing-config path for real,
    # rather than pre-seeding an already-cloned checkout to dodge it.
    with subtest("seed provision's origin repo, including a stand-in signing pubkey"):
        standalone.succeed("git init --bare /root/origin.git")
        standalone.succeed(
            "git init -b main /root/origin-seed && "
            "git -C /root/origin-seed config user.name test && "
            "git -C /root/origin-seed config user.email test@example.com && "
            "mkdir -p /root/origin-seed/nixosConfigurations/shared/secrets "
            "/root/origin-seed/nixosModules/user/ypa766 "
            "/root/origin-seed/nixosModules/user/ypc940"
        )
        standalone.copy_from_host(
            "${bootstrapNixFile}", "/root/origin-seed/nixosConfigurations/bootstrap.nix"
        )
        standalone.copy_from_host(
            "${testAgeKey}/recipient.txt", "/root/origin-seed/master-recipients.txt"
        )
        standalone.copy_from_host("${testAgeKey}/identity.txt", "/root/master-identity.txt")
        standalone.copy_from_host(
            "${testSigningKey}/id_ed25519.pub",
            "/root/origin-seed/nixosModules/user/ypa766/id_ed25519_sk_rk_sign_technosophist.pub",
        )
        standalone.copy_from_host(
            "${testBackupSigningKey}/id_ed25519.pub",
            "/root/origin-seed/nixosModules/user/ypc940/id_ed25519_sk_rk_sign_technosophist.pub",
        )
        standalone.succeed(
            "git -C /root/origin-seed add . && "
            "git -C /root/origin-seed commit -m 'seed fixture' && "
            "git -C /root/origin-seed remote add origin /root/origin.git && "
            "git -C /root/origin-seed push origin HEAD:main"
        )

    with subtest("provision clones fresh, no personal laptop needed"):
        log = standalone.succeed(
            "(yes yes || true) | nixfiles provision provision-host "
            "--nixfiles-path=/root/nixfiles-standalone --nixfiles-git-url=/root/origin.git "
            "--nixfiles-git-branch=main --age-identity=/root/master-identity.txt "
            "2>&1"
        )
        print(f"provision output:\n{log}")

    with subtest("provision configured SSH commit signing on the freshly cloned repo"):
        gitconfig = standalone.succeed("git -C /root/nixfiles-standalone config --list")
        print(f"git config:\n{gitconfig}")
        assert (
            "user.signingkey=/root/nixfiles-standalone/nixosModules/user/ypa766/"
            "id_ed25519_sk_rk_sign_technosophist.pub"
        ) in gitconfig, "expected user.signingkey to point at the cloned repo's own pubkey file"
        assert "commit.gpgsign=true" in gitconfig
        assert "gpg.format=ssh" in gitconfig

    with subtest("provision generated its own hardware-configuration.nix locally"):
        hwconfig = standalone.succeed(
            "cat /root/nixfiles-standalone/nixosConfigurations/provision-host/hardware-configuration.nix"
        )
        print(f"hardware-configuration.nix:\n{hwconfig}")
        assert "virtio_blk" in hwconfig

    with subtest("provision's host config has the right hostname substituted"):
        hostnix = standalone.succeed(
            "cat /root/nixfiles-standalone/nixosConfigurations/provision-host.nix"
        )
        normalized_hostnix = " ".join(hostnix.split())
        print(f"provision-host.nix:\n{hostnix}")
        assert 'networking.hostName = "provision-host"' in hostnix
        assert "./provision-host/hardware-configuration.nix" in hostnix
        assert (
            "services.syncthing.thoughtfull.passwordFile = "
            "./provision-host/secrets/syncthing-passphrase.age;"
        ) in normalized_hostnix

    with subtest("provision generated its own ssh host key after mounting persistent"):
        standalone.succeed("test -f /mnt/persistent/etc/ssh/ssh_host_ed25519_key")
        standalone.succeed(
            "test -f /root/nixfiles-standalone/nixosConfigurations/provision-host/ssh_host_ed25519_key.pub"
        )

    with subtest("provision's secrets are decryptable with its own just-generated host key"):
        for secret in [
            "luks-recovery-passphrase",
            "hashed-user-passphrase",
            "syncthing-passphrase",
        ]:
            standalone.succeed(
                f"age -d -i /mnt/persistent/etc/ssh/ssh_host_ed25519_key "
                f"/root/nixfiles-standalone/nixosConfigurations/provision-host/secrets/{secret}.age"
            )

    with subtest("provision committed and pushed to its origin"):
        log = standalone.succeed("git --git-dir=/root/origin.git log --oneline main")
        print(f"origin log:\n{log}")
        assert "Provision provision-host" in log

    # Ed25519 can't exercise a FIDO2 key's touch/PIN prompt, but that's OpenSSH's concern, not
    # this script's -- verifying end-to-end that the bootstrap commit is a real, valid SSH
    # signature (checked against the stand-in pubkey, independent of what provision itself wrote
    # to gpg.ssh.allowedSignersFile, since it doesn't set one) is what matters here.
    with subtest("provision's bootstrap commit carries a valid SSH signature"):
        standalone.succeed(
            "git -C /root/nixfiles-standalone "
            "-c gpg.ssh.allowedSignersFile=${testAllowedSigners} "
            "verify-commit HEAD"
        )

    with subtest("provision's stubbed disko and nixos-install were invoked correctly"):
        calls = standalone.succeed("cat /tmp/stub-calls.log")
        print(f"stub calls:\n{calls}")
        assert "disko" in calls and "provision-host" in calls
        assert "nixos-install" in calls and "--no-root-password" in calls
        assert calls.index("disko") < calls.index("nixos-install"), (
            "disko must run before nixos-install"
        )
  '';
}
