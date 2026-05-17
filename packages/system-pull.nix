{ lib, pkgs }:
let
  inherit (pkgs)
    awscli2
    coreutils
    jq
    nix
    ;
  inherit (lib) writeFileScriptBin;
in
writeFileScriptBin {
  name = "system-pull";
  replacements = {
    aws = "${awscli2}/bin/aws";
    hostname = "${coreutils}/bin/hostname";
    jq = "${jq}/bin/jq";
    nix_env = "${nix}/bin/nix-env";
    nix_store = "${nix}/bin/nix-store";
    readlink = "${coreutils}/bin/readlink";
  };
  src = ./system-pull/system-pull.bash;
}
