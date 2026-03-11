{ lib, ... }:
arg:
let
  inherit (builtins) isAttrs;
  inherit (lib) dirFiles;
  dir = if isAttrs arg then arg.dir else arg;
  excludes = if isAttrs arg && arg ? excludes then arg.excludes else [ ];
in
map (file: import (dir + "/${file}")) (dirFiles {
  inherit dir excludes;
})
