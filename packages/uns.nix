{ lib, pkgs, ... }:
let
  inherit (pkgs) apg bash;
  inherit (lib) writeFileScriptBin;
in
writeFileScriptBin {
  name = "uns";
  replacements = {
    apg = "${apg}/bin/apg";
    bash = "${bash}/bin/bash";
  };
  src = ./uns/uns.bash;
}
