{ lib, pkgs }:
let
  inherit (pkgs)
    awscli2
    bash
    coreutils
    hostname-debian
    jq
    nix
    ;
  inherit (lib) writeFileScriptBin;
in
writeFileScriptBin {
  name = "system-pull";
  replacements = {
    aws = "${awscli2}/bin/aws";
    bash = "${bash}/bin/bash";
    hostname = "${hostname-debian}/bin/hostname";
    jq = "${jq}/bin/jq";
    nix_env = "${nix}/bin/nix-env";
    nix_store = "${nix}/bin/nix-store";
    readlink = "${coreutils}/bin/readlink";
  };
  src = ./system-pull/system-pull.bash;
}
