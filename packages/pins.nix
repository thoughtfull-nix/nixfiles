{ pkgs, ... }:
let
  inherit (pkgs) apg bash writeScriptBin;
in
writeScriptBin "pins" ''
  #!${bash}/bin/bash
  set -euo pipefail
  ${apg}/bin/apg -a1 -MN -m8 -x8
''
