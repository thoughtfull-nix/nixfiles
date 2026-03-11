{ pkgs, ... }:
src: replacements:
let
  inherit (builtins) readFile;
  inherit (pkgs) replaceVars;
in
(readFile (replaceVars src replacements))
