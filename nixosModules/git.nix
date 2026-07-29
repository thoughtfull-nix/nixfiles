{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (builtins) any map;
  inherit (config.programs) git;
  inherit (config.thoughtfull.user) authorizedKeyFiles;
  inherit (config.thoughtfull.programs.git) signing personal;
  inherit (lib)
    concatMapStringsSep
    fileContents
    filter
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    types
    unique
    ;
  inherit (pkgs.thoughtfull) writeFileScriptBin;
  # The same committed key files used to log into this host (see
  # thoughtfull.user.authorizedKeyFiles) -- same on every machine. Used for
  # the plain github.com host below: this couples git-push identity to the
  # same option that gates interactive/root login (overriding
  # authorizedKeyFiles on a host now affects both at once), and needs no
  # live GitHub API fetch just to clone/push over SSH (e.g. during nixfiles
  # bootstrap, before this repo is even checked out).
  identityFileLines = concatMapStringsSep "\n" (f: "  IdentityFile ${f}") authorizedKeyFiles;
  # technosophist.github.com below is hardcoded to exactly these two files,
  # not the (per-host-overridable) authorizedKeyFiles option above: it's
  # meant to always be technosophist's own identity, regardless of whatever
  # a host has configured its login/authorizedKeyFiles to.
  technosophistAuthFiles = [
    ./user/ypa766/id_ed25519_sk_rk_auth_technosophist.pub
    ./user/ypc940/id_ed25519_sk_rk_auth_technosophist.pub
  ];
  technosophistAuthFileLines = concatMapStringsSep "\n" (
    f: "  IdentityFile ${f}"
  ) technosophistAuthFiles;

  signingConfigured = signing.primaryKeyFile != null;
  signingEnabled = signing.enable && signingConfigured;
  signingKeyFiles = filter (f: f != null) [
    signing.primaryKeyFile
    signing.backupKeyFile
  ];
  # Every email this machine commits as (there can be more than one, e.g. via
  # includeIf blocks for a work identity) is allowed to sign with either key.
  signingEmails = unique (filter (e: e != null) (map (c: c.user.email or null) git.config));
  allowedSignersFile = pkgs.writeText "git-allowed-signers" (
    concatMapStringsSep "\n" (
      email: concatMapStringsSep "\n" (f: ''${email} namespaces="git" ${fileContents f}'') signingKeyFiles
    ) signingEmails
  );
  # Git only supports a single static user.signingKey, so primary-or-backup
  # fallback is implemented via gpg.ssh.defaultKeyCommand instead: git runs
  # this (only when user.signingKey is unset) and expects a `key::<pubkey>`
  # line back. It prefers the primary key, falling back to the backup key, by
  # checking which one (if either) is currently loaded in ssh-agent -- for a
  # FIDO2 key that means whichever YubiKey is plugged in and has had its
  # resident credential loaded. Calls ssh-add bare (relying on PATH, per the
  # module script convention) rather than pinning it via runtimeInputs:
  # programs.ssh already puts openssh on PATH unconditionally, since it's a
  # dependency of the FIDO2 SSH-auth flow this module already builds on.
  mkGitSigningKeyScript =
    name: primaryKeyFile: backupKeyFile:
    writeFileScriptBin {
      inherit name;
      src = ./git/git-signing-key.bash;
      replacements = {
        primary = fileContents primaryKeyFile;
        backup = if backupKeyFile == null then "" else fileContents backupKeyFile;
      };
    };
  gitSigningKeyScript =
    mkGitSigningKeyScript "git-signing-key" signing.primaryKeyFile
      signing.backupKeyFile;

  # The personal identity is always technosophist's own -- only the
  # directory it applies to (personal.directory below) is configurable.
  # Hardcoded rather than optioned, like technosophistAuthFiles above.
  personalEmail = "technosophist@thoughtfull.systems";
  personalName = "technosophist";
  personalSigningPrimaryKeyFile = ./user/ypa766/id_ed25519_sk_rk_sign_technosophist.pub;
  personalSigningBackupKeyFile = ./user/ypc940/id_ed25519_sk_rk_sign_technosophist.pub;
  personalSigningKeyFiles = [
    personalSigningPrimaryKeyFile
    personalSigningBackupKeyFile
  ];
  # Scoped to just the personal email against just the personal keys -- never
  # merged with the main allowedSignersFile above, so a work key can never
  # verify as the personal email (or vice versa).
  personalAllowedSignersFile = pkgs.writeText "git-allowed-signers-personal" (
    concatMapStringsSep "\n" (
      f: ''${personalEmail} namespaces="git" ${fileContents f}''
    ) personalSigningKeyFiles
  );
  personalGitSigningKeyScript =
    mkGitSigningKeyScript "git-signing-key-personal" personalSigningPrimaryKeyFile
      personalSigningBackupKeyFile;
  # A separate gitconfig file, included via includeIf for personal.directory
  # rather than merged into the main /etc/gitconfig, so the personal identity
  # only applies to repos under that directory.
  personalGitConfigFile = pkgs.writeText "personal.gitconfig" (
    lib.generators.toGitINI {
      user = {
        email = personalEmail;
        name = personalName;
      };
      commit.gpgsign = true;
      gpg = {
        format = "ssh";
        ssh = {
          allowedSignersFile = "${personalAllowedSignersFile}";
          defaultKeyCommand = "git-signing-key-personal";
        };
      };
    }
  );
in
{
  config = {
    assertions = [
      {
        assertion = !git.enable || any (c: c ? user.email && c.user.email != null) git.config;
        message = "programs.git.config.user.email is not configured";
      }
      {
        assertion = !git.enable || any (c: c ? user.name && c.user.name != null) git.config;
        message = "programs.git.config.user.name is not configured";
      }
      {
        # An empty list here would silently combine with the unconditional
        # IdentitiesOnly yes below to lock github.com out of SSH auth entirely.
        assertion = authorizedKeyFiles != [ ];
        message = "thoughtfull.user.authorizedKeyFiles is empty, which would lock github.com out of SSH auth";
      }
      {
        assertion = signing.backupKeyFile == null || signingConfigured;
        message = "thoughtfull.programs.git.signing.backupKeyFile is set without primaryKeyFile";
      }
      {
        # Without this, allowedSignersFile (built from signingEmails) silently renders empty --
        # signing still succeeds, but `git verify-commit` fails with no clear signal why.
        assertion = !git.enable || !signingEnabled || signingEmails != [ ];
        message = "thoughtfull.programs.git.signing.primaryKeyFile is set but no programs.git.config.user.email is configured";
      }
    ];
    environment.systemPackages =
      optional signingEnabled gitSigningKeyScript ++ optional personal.enable personalGitSigningKeyScript;
    # mkMerge, not one plain attrset: programs.git.config renders a plain
    # attrset's sections in (Nix's inherently alphabetical) attrset-name
    # order, which would put [includeIf ...] before [user] purely because
    # "includeIf" < "user" -- letting the outer [user] section's email always
    # win over the include regardless of whether its directory actually
    # matched. Wrapping the includeIf block in its own single-element list
    # marks it "ordered" (per programs.git.config's own merge function,
    # above in nixpkgs), which always renders after every plain-attrset
    # ("unordered") contribution -- from this module or any other -- so it's
    # guaranteed to take effect for any directory it matches. (mkDefault
    # isn't usable inside that list element: unlike the unordered bucket,
    # "ordered" definitions bypass the module system's usual priority
    # resolution and are spliced in as literal values, so mkDefault would
    # render as its literal internal representation instead of resolving.)
    programs.git.config = mkMerge (
      [
        {
          commit.gpgsign = mkIf signingEnabled (mkDefault true);
          gpg = mkIf signingEnabled {
            format = mkDefault "ssh";
            ssh = {
              allowedSignersFile = mkDefault "${allowedSignersFile}";
              defaultKeyCommand = mkDefault "git-signing-key";
            };
          };
          init.defaultBranch = mkDefault "main";
          pull.rebase = mkDefault false;
        }
      ]
      ++ optional personal.enable [
        { includeIf."gitdir:${personal.directory}".path = "${personalGitConfigFile}"; }
      ]
    );
    # Reuse a single authenticated connection for github.com. A push can open
    # several separate SSH connections (git-receive-pack, and for LFS-backed
    # repos git-lfs-transfer and git-upload-pack), and with a touch-required
    # FIDO2 key each connection would otherwise demand its own YubiKey touch.
    # Multiplexing collapses them onto one master so they share a single touch.
    # The master lives for the whole push regardless of duration (it always has
    # an active client); ControlPersist only sets how long it lingers idle
    # afterward. 10m mirrors gpg-agent's default-cache-ttl so quick follow-up
    # pushes/pulls reuse it without another touch. The socket lives under
    # /run/user so it is tmpfs-backed and never lands in the persistent store.
    #
    # github.com is restricted to the same committed keys used for
    # interactive/root login (authorizedKeyFiles), so pushes/clones against
    # the real hostname offer only a fixed, predictable identity, regardless
    # of what else is loaded in the agent -- and don't depend on a live
    # GitHub API fetch, so it works even to bootstrap this very repo.
    #
    # technosophist.github.com is a synthetic alias that forwards straight
    # through to github.com, but is hardcoded to always offer exactly
    # technosophist's own auth keys (technosophistAuthFiles above),
    # regardless of what a host has overridden authorizedKeyFiles to.
    # IdentitiesOnly restricts it to exactly those keys, regardless of what
    # else is loaded in the agent, so the identity used here is predictable.
    # %n (the alias as matched, before the HostName rewrite below resolves it
    # to github.com) keeps this ControlPath distinct from the github.com
    # block's, so the two never share a multiplexed connection. %C is left
    # out here: combined with the long alias it can overflow the Unix domain
    # socket path length limit.
    programs.ssh.extraConfig = ''
      Host github.com
      ${identityFileLines}
        IdentitiesOnly yes
        ControlMaster auto
        ControlPath /run/user/%i/ssh-control-%n
        ControlPersist 10m

      Host technosophist.github.com
        HostName github.com
      ${technosophistAuthFileLines}
        IdentitiesOnly yes
        ControlMaster auto
        ControlPath /run/user/%i/ssh-control-%n
        ControlPersist 10m
    '';
    thoughtfull.impermanence.user.directories = mkIf git.enable [ ".config/git" ];
  };
  options.thoughtfull.programs.git.signing = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable SSH commit signing. Defaults on since primaryKeyFile
        and backupKeyFile already default to real, committed keys -- set this
        to false to disable signing on a host without having to null out
        those key file options individually.
      '';
    };
    primaryKeyFile = mkOption {
      type = types.nullOr types.path;
      default = ./user/ypa766/id_ed25519_sk_rk_sign_technosophist.pub;
      description = "Path to the primary FIDO2 SSH public key used for commit signing.";
    };
    backupKeyFile = mkOption {
      type = types.nullOr types.path;
      default = ./user/ypc940/id_ed25519_sk_rk_sign_technosophist.pub;
      description = ''
        Path to the backup FIDO2 SSH public key used for commit signing when
        the primary key is not available (e.g. the primary YubiKey isn't
        plugged in).
      '';
    };
  };
  options.thoughtfull.programs.git.personal = {
    enable = mkEnableOption "the personal (technosophist) git identity for repos under a separate directory tree";
    directory = mkOption {
      type = types.str;
      default = "~/src/technosophist/**";
      description = ''
        gitdir pattern (as used by git-config's includeIf) identifying the
        directory tree the personal identity applies to. The identity
        itself (email, name, signing keys) is fixed to technosophist's own
        and isn't configurable -- see nixosModules/git.nix.
      '';
    };
  };
}
