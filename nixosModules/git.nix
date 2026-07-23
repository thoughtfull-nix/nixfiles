{ config, lib, ... }:
let
  inherit (builtins) any;
  inherit (config.programs) git;
  inherit (lib)
    concatMapStringsSep
    mkDefault
    mkIf
    mkOption
    types
    ;
  cfg = config.thoughtfull.programs.git;
  hasSigningkey = any (c: c ? user.signingkey && c.user.signingkey != null) git.config;
  identityFileLines = concatMapStringsSep "\n" (f: "  IdentityFile ${f}") cfg.identityFiles;
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
    # technosophist.github.com is a synthetic alias that forwards straight
    # through to github.com, offering both authorized keys as identities.
    # IdentitiesOnly restricts it to exactly these two, regardless of what
    # else is loaded in the agent, so the identity used here is predictable.
    # %n (the alias as matched, before the HostName rewrite below resolves it
    # to github.com) keeps this ControlPath distinct from the github.com
    # block's, so the two never share a multiplexed connection.
    programs.ssh.extraConfig = ''
      Host github.com
        ControlMaster auto
        ControlPath /run/user/%i/ssh-control-%C
        ControlPersist 10m

      Host technosophist.github.com
        HostName github.com
      ${identityFileLines}
        IdentitiesOnly yes
        ControlMaster auto
        ControlPath /run/user/%i/ssh-control-%n-%C
        ControlPersist 10m
    '';
    thoughtfull.impermanence.user.directories = mkIf git.enable [ ".config/git" ];
  };
  options.thoughtfull.programs.git.identityFiles = mkOption {
    default = [
      "~/.ssh/id_ed25519_sk_ypa766_auth"
      "~/.ssh/id_ed25519_sk_ypc940_auth"
    ];
    type = types.listOf types.str;
  };
}
