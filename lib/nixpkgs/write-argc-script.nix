{ pkgs, ... }:
with pkgs;
name: src: replacements:
runCommandLocal name { } ''
  mkdir -p $out/bin
  cp "${replaceVars src replacements}" "${name}"
  ${argc}/bin/argc --argc-build "${name}" "$out/bin/${name}"
''
