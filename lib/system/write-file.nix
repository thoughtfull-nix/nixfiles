{ pkgs, ... }:
options@{ name, src, ... }:
let
  inherit (pkgs) replaceVars runCommandLocal;
  mkdest = if options ? directory then "mkdir -p $out${options.directory}" else "";
  replacedSrc = if options ? replacements then replaceVars src options.replacements else src;
  chmod = if options ? executable then "chmod +x ${name}" else "";
  dest = if options ? directory then "$out${options.directory}/${name}" else "$out";
in
runCommandLocal name { } ''
  ${mkdest}
  cp ${replacedSrc} ${name}
  ${chmod}
  cp ${name} ${dest}
''
