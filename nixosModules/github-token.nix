# Workstations no longer evaluate the flake at activation; the daily upgrade
# is driven by `thoughtfull.systemPull`, which fetches a pre-built signed
# closure from the binary cache. Private flake inputs (e.g. kryptonix) are
# resolved in GitHub Actions, not on each host, so a runtime PAT is not
# required for normal operation.
#
# This module remains useful for two paths that still evaluate the flake
# from source:
#   1. Manual `nixos-rebuild` invocations by an operator who wants to build
#      locally instead of waiting for the next CI run.
#   2. Installer / bootstrap flows for a freshly-provisioned host.
# In both cases, set `thoughtfull.githubToken.tokenFile` to the encrypted
# token path.
#
# See `doc/binary-cache.md` for the realized architecture.
{ config, lib, ... }:
let
  inherit (config.thoughtfull) githubToken;
  inherit (lib) mkIf mkOption types;
in
{
  config = mkIf (githubToken.tokenFile != null) {
    age.secrets.github-access-token.file = githubToken.tokenFile;
    nix.extraOptions = ''
      !include ${config.age.secrets.github-access-token.path}
    '';
  };

  options.thoughtfull.githubToken = {
    tokenFile = mkOption {
      default = null;
      description = ''
        Path to an age-encrypted file whose plaintext is a single nix.conf
        line such as `access-tokens = github.com=ghp_xxxxxxxxxxxxxxxxxxxx`.

        The file is decrypted by agenix at activation time and `!include`d
        into nix.conf, so the nix daemon can fetch private GitHub flake
        inputs (e.g. via the `github:owner/repo` URL scheme) without an SSH
        agent.

        Defaults to `null` (disabled). Set to the encrypted file path on
        hosts that still need to evaluate the flake locally — operator
        workstations doing manual `nixos-rebuild` and installer/bootstrap
        images that don't yet have a system closure in the binary cache.
      '';
      type = types.nullOr types.path;
    };
  };
}
