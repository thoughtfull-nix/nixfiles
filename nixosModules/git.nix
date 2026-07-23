{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (builtins) any;
  inherit (config.programs) git;
  inherit (config.thoughtfull.user) github;
  inherit (lib)
    concatMapStringsSep
    filter
    imap0
    mkDefault
    mkIf
    ;
  inherit (lib.thoughtfull) githubKeys;
  hasSigningkey = any (c: c ? user.signingkey && c.user.signingkey != null) git.config;
  # The same two keys on every machine, unlike the per-machine
  # openssh.authorizedKeys.keys pulled from GitHub via thoughtfull.user.
  identityFiles = [
    ./git/id_ed25519_sk_ypa766_auth.pub
    ./git/id_ed25519_sk_ypc940_auth.pub
  ];
  identityFileLines = concatMapStringsSep "\n" (f: "  IdentityFile ${f}") identityFiles;
  # github.com itself is restricted to the keys pulled from GitHub for this
  # machine's user (the same keys used for openssh.authorizedKeys), one file
  # per key so each can be offered as its own IdentityFile.
  githubIdentityFiles = imap0 (i: key: pkgs.writeText "github-com-identity-${toString i}.pub" key) (
    filter (key: key != "") (githubKeys {
      sha256 = github.keysHash;
      username = github.user;
    })
  );
  githubIdentityFileLines = concatMapStringsSep "\n" (f: "  IdentityFile ${f}") githubIdentityFiles;
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
        assertion = githubIdentityFiles != [ ];
        message = "thoughtfull.user.github (user = \"${github.user}\") pulled no keys from GitHub";
      }
    ];
    programs.git.config = {
      commit.gpgsign = mkIf hasSigningkey (mkDefault true);
      gpg = {
        format = mkIf hasSigningkey (mkDefault "openpgp");
        openpgp.program = mkIf hasSigningkey (mkDefault "gpg");
      };
      init.defaultBranch = mkDefault "main";
      pull.rebase = mkDefault false;
    };
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
    # github.com is restricted to the keys pulled from GitHub for this
    # machine's user, so pushes/clones against the real hostname offer only
    # identities GitHub itself already vouches for, regardless of what else is
    # loaded in the agent.
    #
    # technosophist.github.com is a synthetic alias that forwards straight
    # through to github.com, offering both authorized keys as identities.
    # IdentitiesOnly restricts it to exactly these two, regardless of what
    # else is loaded in the agent, so the identity used here is predictable.
    # %n (the alias as matched, before the HostName rewrite below resolves it
    # to github.com) keeps this ControlPath distinct from the github.com
    # block's, so the two never share a multiplexed connection. %C is left
    # out here: combined with the long alias it can overflow the Unix domain
    # socket path length limit.
    programs.ssh.extraConfig = ''
      Host github.com
      ${githubIdentityFileLines}
        IdentitiesOnly yes
        ControlMaster auto
        ControlPath /run/user/%i/ssh-control-%n
        ControlPersist 10m

      Host technosophist.github.com
        HostName github.com
      ${identityFileLines}
        IdentitiesOnly yes
        ControlMaster auto
        ControlPath /run/user/%i/ssh-control-%n
        ControlPersist 10m
    '';
    thoughtfull.impermanence.user.directories = mkIf git.enable [ ".config/git" ];
  };
}
