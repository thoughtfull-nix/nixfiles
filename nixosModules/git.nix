{ config, lib, ... }:
let
  inherit (builtins) any;
  inherit (config.programs) git;
  inherit (config.thoughtfull) user;
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
    ];
    programs.git.config = {
      commit.gpgsign = mkIf hasSigningkey (mkDefault true);
      gpg = {
        format = mkIf hasSigningkey (mkDefault "openpgp");
        openpgp.program = mkIf hasSigningkey (mkDefault "gpg");
      };
      init.defaultBranch = mkDefault "main";
      pull.rebase = mkDefault false;
      user.name = mkDefault user.name;
    };
    thoughtfull.impermanence.user.directories = mkIf git.enable [ ".config/git" ];
  };
}
