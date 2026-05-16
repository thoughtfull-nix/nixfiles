# Future direction: build-and-push instead of fetch-and-build.
#
# At a larger scale (or to keep private source off the hosts entirely), run
# `nixos-rebuild` on a single trusted builder that has read access to
# kryptonix, sign the resulting system closure, push it to a binary cache,
# and have each host `nix copy` + `switch-to-configuration` from the
# substituter. Hosts never fetch private source and need no token. This is
# the model used by Cachix Deploy / `colmena push` / `deploy-rs`. Bigger
# architectural shift, much cleaner blast radius — worth revisiting if the
# fleet grows past a handful of machines.
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
      default = ../nixosConfigurations/shared/secrets/github-access-token.age;
      description = ''
        Path to an age-encrypted file whose plaintext is a single nix.conf
        line such as `access-tokens = github.com=ghp_xxxxxxxxxxxxxxxxxxxx`.

        The file is decrypted by agenix at activation time and `!include`d
        into nix.conf, so the nix daemon can fetch private GitHub flake
        inputs (e.g. via the `github:owner/repo` URL scheme) without an SSH
        agent.

        Set to `null` to disable.

        Bootstrap: a freshly provisioned host has no decrypted token before
        its first `nixos-rebuild`, so the initial install of a host that
        uses private inputs still needs the token in the operator's
        environment (`--option access-tokens 'github.com=…'` or
        `~/.config/nix/nix.conf`).
      '';
      type = types.nullOr types.path;
    };
  };
}
