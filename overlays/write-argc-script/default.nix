{ pkgs, ... }:
name: src: replacements:
let
  inherit (pkgs)
    argc
    bash
    replaceVars
    runCommandLocal
    ;
  inherit (pkgs.lib) getExe;
  bashlib = ./bashlib.bash;
  prefix = replaceVars ./prefix.bash {
    bash = getExe bash;
    bashlib = bashlib;
  };
  outFile = "$out/bin/${name}";
in
runCommandLocal name { } ''
  mkdir -p $(dirname "${outFile}")
  cat "${prefix}" >"${name}"
  cat "${replaceVars src replacements}" >>"${name}"
  ${argc}/bin/argc --argc-build "${name}" "${outFile}"
''
