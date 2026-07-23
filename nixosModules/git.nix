{ config, lib, ... }:
let
  inherit (builtins) any;
  inherit (config.programs) git;
  inherit (lib)
    mkDefault
    mkIf
    ;
  hasSigningkey = any (c: c ? user.signingkey && c.user.signingkey != null) git.config;
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
    programs.ssh.extraConfig = ''
      Host github.com
        ControlMaster auto
        ControlPath /run/user/%i/ssh-control-%C
        ControlPersist 10m
    '';
    thoughtfull.impermanence.user.directories = mkIf git.enable [ ".config/git" ];
  };
}
